//
//  MainScene.m
//  PROJECTNAME
//
//  Created by Viktor on 10/10/13.
//  Copyright (c) 2013 Apportable. All rights reserved.
//

#import "CCPhysics+ObjectiveChipmunk.h"
#import "CCTexture_Private.h"

#import "MainScene.h"
#import "WaterNode.h"


@class LightingLayer;


@implementation CCNode(LightingLayer)

-(LightingLayer *)lightingLayer
{
	return self.parent.lightingLayer;
}

@end


@implementation MainScene {
	CCPhysicsNode *_physicsNode;
}

-(void)onEnter
{
//	_physicsNode.debugDraw = YES;
	_physicsNode.collisionDelegate = self;
	
	[super onEnter];
}

-(BOOL)ccPhysicsCollisionPreSolve:(CCPhysicsCollisionPair *)pair floater:(CCNode *)floater water:(WaterNode *)water
{
	[water applyBuoyancy:pair];
	
	return NO;
}

@end


@interface BoundsNode : CCNode @end
@implementation BoundsNode
-(void)onEnter
{
	CGSize size = self.contentSizeInPoints;
	self.physicsBody = [CCPhysicsBody bodyWithPolylineFromRect:CGRectMake(0.0, 0.0, size.width, size.height) cornerRadius:0.0];
	
	[super onEnter];
}

@end


@protocol Light
@property(nonatomic, readonly) float lightRadius;
@property(nonatomic, readonly) GLKVector4 lightColor;
@end


@protocol Occluder
@property(nonatomic, readonly) CCVertex *occluderVertexes;
@property(nonatomic, readonly) int occluderVertexCount;
@end


@interface LightingLayer : CCNode @end
@implementation LightingLayer {
	NSMutableArray *_occluders;
	NSMutableArray *_lights;
	
	CCRenderTexture *_lightMapBuffer;
	CCRenderState *_shadowRenderState;
	CCRenderState *_lightRenderState;
}

-(id)init
{
	if((self = [super init])){
		_occluders = [NSMutableArray array];
		_lights = [NSMutableArray array];
		
		_shadowRenderState = [CCRenderState renderStateWithBlendMode:[CCBlendMode disabledMode] shader:[CCShader positionColorShader] mainTexture:nil];
		
		CCBlendMode *lightBlend = [CCBlendMode blendModeWithOptions:@{
			CCBlendFuncSrcColor: @(GL_ONE_MINUS_DST_ALPHA),
			CCBlendFuncDstColor: @(GL_ONE),
		}];
		
		CCShader *lightShader = [[CCShader alloc] initWithFragmentShaderSource:CC_GLSL(
			void main(){
				gl_FragColor = (1.0 - length(cc_FragTexCoord1))*cc_FragColor;
			}
		)];
		
		_lightRenderState = [CCRenderState renderStateWithBlendMode:lightBlend shader:lightShader mainTexture:nil];
	}
	
	return self;
}

-(void)onEnter
{
	// TODO Could cut down on fillrate a little by using a screen sized texture.
	CGSize size = [CCDirector sharedDirector].designSize;
	_lightMapBuffer = [CCRenderTexture renderTextureWithWidth:size.width height:size.height];
	_lightMapBuffer.contentScale /= 2;
	[_lightMapBuffer.texture setAntiAliasTexParameters];
	
	CCSprite *rtSprite = _lightMapBuffer.sprite;
	rtSprite.anchorPoint = CGPointZero;
	rtSprite.blendMode = [CCBlendMode multiplyMode];
	
	[self addChild:_lightMapBuffer z:-100];
	
	[super onEnter];
}

-(LightingLayer *)lightingLayer
{
	return self;
}

-(void)addLight:(CCNode<Light> *)light
{
	[_lights addObject:light];
}

-(void)removeLight:(CCNode<Light> *)light
{
	[_lights removeObject:light];
}

-(void)addOccluder:(CCNode<Occluder> *)occluder
{
	[_occluders addObject:occluder];
}

-(void)removeOccluder:(CCNode<Occluder> *)occluder
{
	[_occluders removeObject:occluder];
}

-(void)maskLight:(CCNode<Light> *)light renderer:(CCRenderer *)renderer worldToLight:(CGAffineTransform)worldToLight projection:(GLKMatrix4)projection
{
	for(CCNode<Occluder> *occluder in _occluders){
		CCVertex *verts = occluder.occluderVertexes;
		int count = occluder.occluderVertexCount;
		CGAffineTransform toLight = CGAffineTransformConcat(occluder.nodeToWorldTransform, worldToLight);
		
		GLKMatrix4 occluderMatrix = GLKMatrix4Make(
			 toLight.a,  toLight.b, 0.0f, 0.0f,
			 toLight.c,  toLight.d, 0.0f, 0.0f,
			      0.0f,       0.0f, 1.0f, 0.0f,
			toLight.tx, toLight.ty, 0.0f, 1.0f
		);
		
		CGPoint lightPosition = light.position;
		float lx = lightPosition.x, ly = lightPosition.y;
		GLKMatrix4 shadowMatrix = GLKMatrix4Multiply(GLKMatrix4Make(
			1.0f, 0.0f, 0.0f,  0.0f,
			0.0f, 1.0f, 0.0f,  0.0f,
			 -lx,  -ly, 0.0f, -1.0f,
			0.0f, 0.0f, 0.0f,  1.0f
		), occluderMatrix);
		
		GLKMatrix4 shadowProjection = GLKMatrix4Multiply(projection, shadowMatrix);
		
		CCRenderBuffer buffer = [renderer enqueueTriangles:2*count andVertexes:2*count withState:_shadowRenderState];
		
		for(int i=0, j=count-1; i<count; j=i, i++){
			CCVertex v = verts[i];
			CCRenderBufferSetVertex(buffer, 2*i + 0, CCVertexApplyTransform(v, &shadowProjection));
			
			v.position.z = 1.0;
			CCRenderBufferSetVertex(buffer, 2*i + 1, CCVertexApplyTransform(v, &shadowProjection));
			
			CCRenderBufferSetTriangle(buffer, 2*i + 0, 2*i + 0, 2*i + 1, 2*j + 0);
			CCRenderBufferSetTriangle(buffer, 2*i + 1, 2*j + 1, 2*j + 0, 2*i + 1);
		}
	}
}

static inline CCVertex
LightVertex(GLKMatrix4 transform, GLKVector2 pos, GLKVector2 texCoord, GLKVector4 color4)
{
	const GLKVector2 zero2 = {{0.0f, 0.0f}};
	return (CCVertex){GLKMatrix4MultiplyVector4(transform, GLKVector4Make(pos.x, pos.y, 0.0f, 1.0f)), texCoord, zero2, color4};
}

-(void)visit:(CCRenderer *)renderer parentTransform:(const GLKMatrix4 *)parentTransform
{
	CGAffineTransform worldToLight = self.worldToNodeTransform;
	GLKMatrix4 projection = _lightMapBuffer.projection;
	
	float ambient = 0.3;
	[_lightMapBuffer beginWithClear:ambient g:ambient b:ambient a:0];
		for(CCNode<Light> *light in _lights){
			// TODO enabling scissoring could reduce fillrate usage here.
			
			[renderer enqueueBlock:^{
				// Disable drawing the back faces to cut down on fillrate.
				glEnable(GL_CULL_FACE);
				glCullFace(GL_BACK);
				
				// The shadow mask should only affect the alpha chanel.
				glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE);
			} debugLabel:@"LightingLayer: Set shadow mask drawing mode."];
			
			// Clear the alpha and draw the shadow mask.
			[renderer enqueueClear:GL_COLOR_BUFFER_BIT color:GLKVector4Make(0.0f, 0.0f, 0.0f, 0.0f) depth:0.0f stencil:0];
			[self maskLight:light renderer:renderer worldToLight:worldToLight projection:projection];
			
			// Reset culling and color masking.
			[renderer enqueueBlock:^{
				glDisable(GL_CULL_FACE);
				glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
			} debugLabel:@"LightingLayer: Restore mode."];
			
			// Render a quad for the light.
			CGPoint pos = light.position;
			float radius = light.lightRadius;
			GLKVector4 color4 = light.lightColor;
			
			CCRenderBuffer buffer = [renderer enqueueTriangles:2 andVertexes:4 withState:_lightRenderState];
			CCRenderBufferSetVertex(buffer, 0, LightVertex(projection, GLKVector2Make(pos.x - radius, pos.y - radius), GLKVector2Make(-1, -1), color4));
			CCRenderBufferSetVertex(buffer, 1, LightVertex(projection, GLKVector2Make(pos.x - radius, pos.y + radius), GLKVector2Make(-1,  1), color4));
			CCRenderBufferSetVertex(buffer, 2, LightVertex(projection, GLKVector2Make(pos.x + radius, pos.y + radius), GLKVector2Make( 1,  1), color4));
			CCRenderBufferSetVertex(buffer, 3, LightVertex(projection, GLKVector2Make(pos.x + radius, pos.y - radius), GLKVector2Make( 1, -1), color4));
			CCRenderBufferSetTriangle(buffer, 0, 0, 1, 2);
			CCRenderBufferSetTriangle(buffer, 1, 0, 2, 3);
		}
	[_lightMapBuffer end];
	
	[super visit:renderer parentTransform:parentTransform];
}

@end


@interface BoxSprite : CCSprite<Occluder> @end
@implementation BoxSprite {
	CCVertex *_occluderVertexes;
	int _occluderVertexCount;
}

-(void)dealloc
{
	free(_occluderVertexes);
}

-(void)onEnter
{
	CCPhysicsBody *body = self.physicsBody;
	body.collisionType = @"floater";
	
	[self.lightingLayer addOccluder:self];
	
	[super onEnter];
	
	// Ooof
	ChipmunkPolyShape *poly = self.physicsBody.body.shapes[0];
	_occluderVertexCount = poly.count;
	_occluderVertexes = realloc(_occluderVertexes, _occluderVertexCount*sizeof(*_occluderVertexes));
	
	for(int i=0; i<_occluderVertexCount; i++){
		cpVect v = [poly getVertex:i];
		const GLKVector2 zero2 = {{0, 0}};
		const GLKVector4 zero4 = {{0, 0, 0, 1}};
		
		_occluderVertexes[i] = (CCVertex){GLKVector4Make(v.x, v.y, 0.0f, 1.0f), zero2, zero2, zero4};
	}
}

-(void)onExit
{
	[self.lightingLayer removeOccluder:self];
	
	[super onExit];
}

-(CCVertex *)occluderVertexes
{
	return _occluderVertexes;
}

-(int)occluderVertexCount
{
	return _occluderVertexCount;
}

@end


@interface AlgaeBlob : CCSprite<Light> @end
@implementation AlgaeBlob

-(void)onEnter
{
	CCPhysicsBody *body = self.physicsBody;
	body.collisionType = @"floater";
	
	[self.lightingLayer addLight:self];
	
	[super onEnter];
}

-(void)onExit
{
	[self.lightingLayer removeLight:self];
	
	[super onExit];
}

-(float)lightRadius
{
	return 250.0;
}

-(GLKVector4)lightColor
{
	return GLKVector4Make(0.5, 1, 0.5, 1);
}

@end
