#import "CCDirector_Private.h"
#import "CCTextureCache.h"
#import "CCTexture_Private.h"
#import "CCRenderer_Private.h"

#import "LightingLayer.h"


@implementation CCNode(LightingLayer)

-(LightingLayer *)lightingLayer
{
	return self.parent.lightingLayer;
}

@end


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
		
		_shadowRenderState = [CCRenderState renderStateWithBlendMode:[CCBlendMode disabledMode] shader:[CCShader positionColorShader] mainTexture:[CCTexture none]];
		
		CCBlendMode *lightBlend = [CCBlendMode blendModeWithOptions:@{
			CCBlendFuncSrcColor: @(GL_DST_ALPHA),
			CCBlendFuncDstColor: @(GL_ONE),
		}];
		
		CCTexture *lightTexture = [[CCTextureCache sharedTextureCache] addImage:@"LightAttenuation.psd"];
		_lightRenderState = [CCRenderState renderStateWithBlendMode:lightBlend shader:[CCShader positionTextureColorShader] mainTexture:lightTexture];
	}
	
	return self;
}

-(void)onEnter
{
	CGRect viewport = [CCDirector sharedDirector].viewportRect;
	_lightMapBuffer = [CCRenderTexture renderTextureWithWidth:ceilf(viewport.size.width) height:ceilf(viewport.size.height)];
	_lightMapBuffer.position = viewport.origin;
	_lightMapBuffer.contentScale /= 2;
	[_lightMapBuffer.texture setAntiAliasTexParameters];
	
	_lightMapBuffer.projection = GLKMatrix4MakeOrtho(CGRectGetMinX(viewport), CGRectGetMaxX(viewport), CGRectGetMaxY(viewport), CGRectGetMinY(viewport), -1024, 1024);
	
	CCSprite *rtSprite = _lightMapBuffer.sprite;
	rtSprite.anchorPoint = CGPointZero;
	rtSprite.blendMode = [CCBlendMode blendModeWithOptions:@{
		CCBlendFuncSrcColor: @(GL_DST_COLOR),
		CCBlendFuncDstColor: @(GL_SRC_COLOR),
	}];
	
	[self addChild:_lightMapBuffer z:NSIntegerMax];
	
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
	
	float ambient = 0.2*0.5;
	[_lightMapBuffer beginWithClear:ambient g:ambient b:ambient a:1.0f];
		for(CCNode<Light> *light in _lights){
			CGPoint pos = light.position;
			float radius = light.lightRadius;
			GLKVector4 color4 = GLKVector4MultiplyScalar(light.lightColor, 0.5);
			
			[renderer enqueueBlock:^{
				// Disable drawing the front faces to cut down on fillrate.
				glEnable(GL_CULL_FACE);
				glCullFace(GL_FRONT);
				
				// The shadow mask should only affect the alpha chanel.
				glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE);
			} debugLabel:@"LightingLayer: Set shadow mask drawing mode."];
			
			// Clear the alpha and draw the shadow mask.
			[renderer enqueueClear:GL_COLOR_BUFFER_BIT color:GLKVector4Make(0.0f, 0.0f, 0.0f, 1.0f) depth:0.0f stencil:0];
			[self maskLight:light renderer:renderer worldToLight:worldToLight projection:projection];
			
			// This is kind of a nasty hack...
			for(CCNode *occluder in _occluders){
				[occluder visit:renderer parentTransform:&projection];
			}
			
			// Reset culling and color masking.
			[renderer enqueueBlock:^{
				glDisable(GL_CULL_FACE);
				glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
			} debugLabel:@"LightingLayer: Restore mode."];
			
			// Render a quad for the light.
			CCRenderBuffer buffer = [renderer enqueueTriangles:2 andVertexes:4 withState:_lightRenderState];
			CCRenderBufferSetVertex(buffer, 0, LightVertex(projection, GLKVector2Make(pos.x - radius, pos.y - radius), GLKVector2Make(0, 0), color4));
			CCRenderBufferSetVertex(buffer, 1, LightVertex(projection, GLKVector2Make(pos.x - radius, pos.y + radius), GLKVector2Make(0, 1), color4));
			CCRenderBufferSetVertex(buffer, 2, LightVertex(projection, GLKVector2Make(pos.x + radius, pos.y + radius), GLKVector2Make(1, 1), color4));
			CCRenderBufferSetVertex(buffer, 3, LightVertex(projection, GLKVector2Make(pos.x + radius, pos.y - radius), GLKVector2Make(1, 0), color4));
			CCRenderBufferSetTriangle(buffer, 0, 0, 1, 2);
			CCRenderBufferSetTriangle(buffer, 1, 0, 2, 3);
		}
	[_lightMapBuffer end];
	
	[super visit:renderer parentTransform:parentTransform];
}

@end
