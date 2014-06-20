#import "WaterNode.h"
#import "CCPhysics+ObjectiveChipmunk.h"

//#import "CCNode_Private.h"
//#import "CCSprite_Private.h"
#import "CCTexture_Private.h"
#import "CCDirector_Private.h"

static const cpFloat FLUID_DENSITY = 1.5e-3;
static const cpFloat FLUID_DRAG = 1.0e0;

@implementation WaterNode {
	cpSpace *_space;
	
	// Number of points in the water surface.
	NSUInteger _surfaceCount;
	
	// Current and previous water surface height samples.
	float *_surface, *_prevSurface;
}

-(void)onEnter
{
	_space = self.physicsNode.space.space;
	
	CCPhysicsBody *body = self.physicsBody;
	body.sensor = YES;
	body.collisionType = @"water";
	
	_surfaceCount = 568/4 + 1;
	_surface = calloc(2*_surfaceCount, sizeof(*_surface));
	_prevSurface = _surface + _surfaceCount;
	
	// Set up a matrix to convert from vertex positions to texture coordinates for the refraction.

	// This is a private director method. It's only used for aligning the BG texture coordinates for the distortion shader.
	// I should really find a cleaner way to do this. :-/
	CGRect viewport = [CCDirector sharedDirector].viewportRect;
	
	CGSize designSize = [CCDirector sharedDirector].designSize;
	self.shaderUniforms[@"texMatrix"] = [NSValue valueWithGLKMatrix4:GLKMatrix4Invert(GLKMatrix4MakeOrtho(
		CGRectGetMinX(viewport)/designSize.width,
		CGRectGetMaxX(viewport)/designSize.width,
		CGRectGetMinY(viewport)/designSize.height,
		CGRectGetMaxY(viewport)/designSize.height,
		-1.0f, 1.0f
	), NULL)];
	
	// Set the cave background texture.
	self.shaderUniforms[@"refractedBackground"] = [CCTexture textureWithFile:@"CaveBackground.psd"];
	
	CCTexture *noise = [CCTexture textureWithFile:@"Noise.psd"];
	// Currently a private texture method. We'll expose a better way to set up texture parameters soon.
	noise.texParameters = &((ccTexParams){GL_LINEAR, GL_LINEAR, GL_REPEAT, GL_REPEAT});
	
	self.shaderUniforms[@"noise"] = noise;
	self.shaderUniforms[@"noiseSize"] = [NSValue valueWithCGSize:CC_SIZE_SCALE(noise.contentSize, 4.0)];
	
	self.shader = [[CCShader alloc] initWithVertexShaderSource:CC_GLSL(
		uniform mat4 texMatrix;
		uniform vec2 noiseSize;
		
		varying vec2 noiseCoords;
		varying vec2 bgTexCoords;
		
		void main(){
			gl_Position = cc_Position;
			cc_FragTexCoord1 = cc_TexCoord1;
			cc_FragColor = cc_Color;
			
			vec2 offset = mod(vec2(50.0*cc_Time[0], 50.0*cc_SinTime[1]), noiseSize);
			noiseCoords = ((cc_ProjectionInv*cc_Position).xy + offset)/noiseSize;
			
			bgTexCoords = (texMatrix*cc_Position).xy;
		}
	) fragmentShaderSource:CC_GLSL(
		uniform sampler2D noise;
		uniform sampler2D refractedBackground;
		
		varying highp vec2 noiseCoords;
		varying highp vec2 bgTexCoords;
		
		void main(){
			vec4 water = texture2D(cc_MainTexture, cc_FragTexCoord1);
			
			mediump vec2 offset = 2.0*texture2D(noise, noiseCoords).xy - 1.0;
			vec4 bg = texture2D(refractedBackground, bgTexCoords + 0.020*offset);
			
			gl_FragColor = vec4(mix(bg, water, 0.85).rgb, water.a)*cc_FragColor;
		}
	)];
	
	[super onEnter];
}

-(void)dealloc
{
	// Both surface pointers point into the same buffer.
	// Free the one with the lowest pointer.
	free(MIN(_surface, _prevSurface));
}

static inline cpFloat
k_scalar_body(cpBody *body, cpVect point, cpVect n)
{
	cpFloat rcn = cpvcross(cpvsub(point, cpBodyGetPosition(body)), n);
	return 1.0f/cpBodyGetMass(body) + rcn*rcn/cpBodyGetMoment(body);
}

-(void)applyBuoyancy:(CCPhysicsCollisionPair *)pair
{
	CCPhysicsShape *floaterShape, *waterShape;
	[pair shapeA:&floaterShape shapeB:&waterShape];
	
	cpBB fluidBounds = cpShapeGetBB(waterShape.shape.shape);
	cpFloat fluidLevel = fluidBounds.t;
	
	cpShape *poly = floaterShape.shape.shape;
	
	cpBody *body = cpShapeGetBody(poly);
	
	// Clip the polygon against the fluid level
	int count = cpPolyShapeGetCount(poly);
	int clippedCount = 0;
	cpVect clipped[count + 1];

	for(int i=0, j=count-1; i<count; j=i, i++){
		cpVect a = cpBodyLocalToWorld(body, cpPolyShapeGetVert(poly, j));
		cpVect b = cpBodyLocalToWorld(body, cpPolyShapeGetVert(poly, i));
		
		if(a.y < fluidLevel){
			clipped[clippedCount] = a;
			clippedCount++;
		}
		
		cpFloat a_level = a.y - fluidLevel;
		cpFloat b_level = b.y - fluidLevel;
		
		if(a_level*b_level < 0.0f){
			cpFloat t = cpfabs(a_level)/(cpfabs(a_level) + cpfabs(b_level));
			
			clipped[clippedCount] = cpvlerp(a, b, t);
			clippedCount++;
		}
	}
	
	// Calculate buoyancy from the clipped polygon area
	cpFloat clippedArea = cpAreaForPoly(clippedCount, clipped, 0.0f);
	if(clippedArea < 1.0) return;
	
	cpFloat displacedMass = clippedArea*FLUID_DENSITY;
	cpVect centroid = cpCentroidForPoly(clippedCount, clipped);
	
	cpFloat dt = cpSpaceGetCurrentTimeStep(_space);
	cpVect g = cpSpaceGetGravity(_space);
	
	// Apply the buoyancy force as an impulse.
	cpBodyApplyImpulseAtWorldPoint(body, cpvmult(g, -displacedMass*dt), centroid);
	
	// Apply linear damping for the fluid drag.
	cpVect v_centroid = cpBodyGetVelocityAtWorldPoint(body, centroid);
	cpFloat k = k_scalar_body(body, centroid, cpvnormalize(v_centroid));
	cpFloat damping = clippedArea*FLUID_DRAG*FLUID_DENSITY;
	cpFloat v_coef = cpfexp(-damping*dt*k); // linear drag
//	cpFloat v_coef = 1.0/(1.0 + damping*dt*cpvlength(v_centroid)*k); // quadratic drag
	cpBodyApplyImpulseAtWorldPoint(body, cpvmult(cpvsub(cpvmult(v_centroid, v_coef), v_centroid), 1.0/k), centroid);
	
	// Apply angular damping for the fluid drag.
	cpVect cog = cpBodyLocalToWorld(body, cpBodyGetCenterOfGravity(body));
	cpFloat w_damping = cpMomentForPoly(FLUID_DRAG*FLUID_DENSITY*clippedArea, clippedCount, clipped, cpvneg(cog), 0.0f);
	cpBodySetAngularVelocity(body, cpBodyGetAngularVelocity(body)*cpfexp(-w_damping*dt/cpBodyGetMoment(body)));
	
	// Disturb the water's surface.
	cpVect left = cpv(fluidBounds.l, fluidBounds.t);
	cpVect right = cpv(fluidBounds.r, fluidBounds.t);

	cpSegmentQueryInfo infoL = {}, infoR = {};
	if(
		cpShapeSegmentQuery(poly, left, right, 0.0, &infoL) &&
		cpShapeSegmentQuery(poly, right, left, 0.0, &infoR)
	){
		float nodeToIndex = (float)_surfaceCount/_contentSize.width/2.0f;
		float center = (infoL.point.x + infoR.point.x)*nodeToIndex;
		float radius = (infoR.point.x - infoL.point.x)*nodeToIndex;
		float dY = dt*cpBodyGetVelocity(body).y;
		
		float rigidEffect = 0.05;
		float lerpCoef = 1.0f - cpfpow(rigidEffect, dt);
		for(int i = floorf(center - radius), imax = ceilf(center + radius); i < imax; i++){
			float t = clampf((i - center)/radius, -1.0f, 1.0f);
			float blend = t*t*(t*t - 2.0f) + 1.0f;
			
			float prevSurface = _prevSurface[i];
			_surface[i] = cpflerp(_surface[i] - prevSurface, dY, blend*lerpCoef) + prevSurface;
		}
	}
}

static inline float
Diffuse(float diff, float damp, float prev, float curr, float next){
	return (curr*diff + ((prev + next)*0.5f)*(1.0f - diff))*damp;
}

-(void)fixedUpdate:(CCTime)delta
{
	float *dst = _prevSurface;
	float *h0 = _prevSurface;
	float *h1 = _surface;
	NSUInteger count = _surfaceCount;
	
	// Integrate the water surface
	for(int i=0; i<count; i++){
//	const float clamp = 15.0;
//		dst[i] = cpfclamp(2.0*h1[i] - h0[i], -clamp, clamp);
		dst[i] = 2.0*h1[i] - h0[i];
	}
	
	// Diffuse the surface
	float prev = dst[0];
	float curr = dst[0];
	float next = dst[1];
	
	const float diffusion = 0.5;
	const float _damping = powf(0.9, delta);

	dst[0] = Diffuse(diffusion, _damping, prev, curr, next);

	for(int i=1; i<(count - 1); ++i){
		prev = curr;
		curr = next;
		next = dst[i + 1];

		dst[i] = Diffuse(diffusion, _damping, prev, curr, next);
	}
	
	prev = curr;
	curr = next;
	dst[count - 1] = Diffuse(diffusion, _damping, prev, curr, next);
	
	// Swap the buffers.
	_surface = dst;
	_prevSurface = h1;
}

-(void)draw:(CCRenderer *)renderer transform:(const GLKMatrix4 *)transform
{
	const CCSpriteVertexes *verts = self.vertexes;
	
	CCVertex bl = CCVertexApplyTransform(verts->bl, transform);
	CCVertex br = CCVertexApplyTransform(verts->br, transform);
	CCVertex tr = CCVertexApplyTransform(verts->tr, transform);
	CCVertex tl = CCVertexApplyTransform(verts->tl, transform);
	
	GLKVector4 ybasis = GLKMatrix4MultiplyVector4(*transform, GLKVector4Make(0.0, 1.0, 0.0, 0.0));
	
	NSUInteger count = (_surfaceCount - 1);
	float *surface = _surface;
	
	CCRenderBuffer buffer =[renderer enqueueTriangles:2*count andVertexes:2*_surfaceCount withState:self.renderState globalSortOrder:0];
	CCRenderBufferSetVertex(buffer, 0, bl);
	
	CCVertex v1 = tl;
	v1.position = GLKVector4Add(v1.position, GLKVector4MultiplyScalar(ybasis, surface[0]));
	CCRenderBufferSetVertex(buffer, 1, v1);
	
	
	for(int i=0; i<count; i++){
		float t = (float)(i + 1)/(float)count;
		CCRenderBufferSetVertex(buffer, 2*i + 2, CCVertexLerp(bl, br, t));
		
		CCVertex b = CCVertexLerp(tl, tr, t);
		b.position = GLKVector4Add(b.position, GLKVector4MultiplyScalar(ybasis, surface[i + 1]));
		b.texCoord1.x += (surface[i+1] - surface[i])/100.0f;
		CCRenderBufferSetVertex(buffer, 2*i + 3, b);
		
		CCRenderBufferSetTriangle(buffer, 2*i + 0, 2*i + 0, 2*i + 1, 2*i + 2);
		CCRenderBufferSetTriangle(buffer, 2*i + 1, 2*i + 1, 2*i + 2, 2*i + 3);
	}
}

@end
