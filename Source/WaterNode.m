#import "WaterNode.h"
#import "CCPhysics+ObjectiveChipmunk.h"

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
	
	for(int i=0; i<_surfaceCount; i++){
		_surface[i] = 20.0f*sinf(i/10.0f);
		_prevSurface[i] = 20.0f*sinf(i/10.0f - 0.05);
	}
	
	_drawNode = [CCDrawNode node];
	[self addChild:_drawNode];
	
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
	
	cpShape *poly = floaterShape.shape.shape;
	cpFloat fluidLevel = cpShapeGetBB(waterShape.shape.shape).t;
	
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
	
	// TODO Temp drawing code.
	[_drawNode clear];
	CCColor *color = [CCColor redColor];
	CGSize size = self.contentSizeInPoints;
	float coef = size.width/_surfaceCount;
	float offset = size.height;
	
	for(int i=1; i<count; i++){
		[_drawNode drawSegmentFrom:ccp((i - 1)*coef, dst[i-1] + offset) to:ccp(i*coef, dst[i] + offset) radius:1.0 color:color];
	}
}

//-(float)dx{return _bounds.size.width/(GLfloat)(_surfaceCount - 1);}
//
//- (void)draw {
//	// It would be better to run these on a fixed timestep.
//	// As an GFX only effect it doesn't really matter though.
//	[self vertlet];
//	[self diffuse];
//	
//	GLfloat dx = [self dx];
//	GLfloat top = _bounds.size.height;
//	
//	// Build a vertex array and render it.
//	struct Vertex{GLfloat x,y;};
//	struct Vertex verts[_count*2];
//	for(int i=0; i<_count; i++){
//		GLfloat x = i*dx;
//		verts[2*i + 0] = (struct Vertex){x, 0};
//		verts[2*i + 1] = (struct Vertex){x, top + _h2[i]};
//	}
//	
//	glDisableClientState(GL_COLOR_ARRAY);
//	glDisableClientState(GL_TEXTURE_COORD_ARRAY);
//	
//	glDisable(GL_TEXTURE_2D);
//	
//	GLfloat r = 105.0f/255.0f;
//	GLfloat g = 193.0f/255.0f;
//	GLfloat b = 212.0f/255.0f;
//	GLfloat a = 0.3f;
//	glColor4f(r*a, g*a, b*a, a);
//	
//	glVertexPointer(2, GL_FLOAT, 0, verts);
//	
//	glPushMatrix(); {
//		glScalef(CC_CONTENT_SCALE_FACTOR(), CC_CONTENT_SCALE_FACTOR(), 1.0);
//		glTranslatef(_bounds.origin.x, _bounds.origin.y, 0.0);
//		
//		glDrawArrays(GL_TRIANGLE_STRIP, 0, _count*2);
//	} glPopMatrix();
//	
//	glEnableClientState(GL_COLOR_ARRAY);
//	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
//	glEnable(GL_TEXTURE_2D);
//	
//	glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
//}
//
//-(void)makeSplashAt:(float)x;
//{
//	// Changing the values of heightfield in h2 will make the waves move.
//	// Here I only change one column, but you get the idea.
//	// Change a bunch of the heights using a nice smoothing function for a better effect.
//	
//	int index = MAX(0, MIN((int)(x/[self dx]), _count - 1));
//	_h2[index] += CCRANDOM_MINUS1_1()*20.0;
//}

@end
