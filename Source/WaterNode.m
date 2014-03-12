#import "WaterNode.h"
#import "CCPhysics+ObjectiveChipmunk.h"
#import "CCNode_Private.h"
#import "CCSprite_Private.h"

static const cpFloat FLUID_DENSITY = 1.5e-3;
static const cpFloat FLUID_DRAG = 1.0e0;

@implementation WaterNode {
	cpSpace *_space;
	
	// Number of points in the water surface.
	NSUInteger _surfaceCount;
	
	// Current and previous water surface height samples.
	float *_surface, *_prevSurface;
	
	CCDrawNode *_drawNode;
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
	
//	for(int i=0; i<_surfaceCount; i++){
//		_surface[i] = 20.0f*sinf(i/10.0f);
//		_prevSurface[i] = 20.0f*sinf(i/10.0f - 0.05);
//	}
	
	_drawNode = [CCDrawNode node];
	[self addChild:_drawNode];
	
//	[self scheduleBlock:^(CCTimer *timer) {
//		float center = _surfaceCount*CCRANDOM_0_1();
//		float radius = 1.5f;
//		
//		for(int i=0; i<_surfaceCount; i++){
//			float t = clampf((i - center)/radius, -1.0f, 1.0f);
//			float f = t*t*(t*t - 2.0f) + 1.0f;
//			
//			_surface[i] -= 2.0f*f;
//		}
//		
//		[timer repeatOnceWithInterval:5.0];
//	} delay:1.0];
	
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
		CCColor *color = [CCColor redColor];
		[_drawNode drawDot:CPV_TO_CCP(infoL.point) radius:2.0 color:color];
		[_drawNode drawDot:CPV_TO_CCP(infoR.point) radius:2.0 color:color];
		
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
	[_drawNode clear];
	
	
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
	CCVertex *spriteVerts = self.verts;
	
	CCVertex bl = CCVertexApplyTransform(spriteVerts[0], transform);
	CCVertex br = CCVertexApplyTransform(spriteVerts[1], transform);
	CCVertex tr = CCVertexApplyTransform(spriteVerts[2], transform);
	CCVertex tl = CCVertexApplyTransform(spriteVerts[3], transform);
	
	GLKVector4 ybasis = GLKMatrix4MultiplyVector4(*transform, GLKVector4Make(0.0, 1.0, 0.0, 0.0));
	
	NSUInteger count = (_surfaceCount - 1);
	float *surface = _surface;
	
	CCRenderBuffer buffer =[renderer enqueueTriangles:2*count andVertexes:2*_surfaceCount withState:self.renderState];
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
