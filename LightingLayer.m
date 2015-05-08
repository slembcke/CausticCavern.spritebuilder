#import "CCDirector_Private.h"
#import "CCTexture_Private.h"

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
	CCRenderState *_shadowClearRenderState;
	CCRenderState *_lightRenderState;
}

-(id)init
{
	if((self = [super init])){
		_occluders = [NSMutableArray array];
		_lights = [NSMutableArray array];
		
		CCBlendMode *shadowBlend = [CCBlendMode blendModeWithOptions:@{
			CCBlendEquationColor: @(GL_FUNC_ADD),
			CCBlendFuncSrcColor: @(GL_ZERO),
			CCBlendFuncDstColor: @(GL_ONE),
			CCBlendEquationAlpha: @(GL_FUNC_REVERSE_SUBTRACT),
			CCBlendFuncSrcAlpha: @(GL_ONE),
			CCBlendFuncDstAlpha: @(GL_ONE),
		}];
		
		_shadowRenderState = [CCRenderState renderStateWithBlendMode:shadowBlend shader:[CCShader shaderNamed:@"SoftShadow"] mainTexture:[CCTexture none]];
		
		CCBlendMode *shadowClearBlend = [CCBlendMode blendModeWithOptions:@{
			CCBlendEquationColor: @(GL_FUNC_ADD),
			CCBlendFuncSrcColor: @(GL_ZERO),
			CCBlendFuncDstColor: @(GL_ONE),
			CCBlendEquationAlpha: @(GL_FUNC_ADD),
			CCBlendFuncSrcAlpha: @(GL_ONE),
			CCBlendFuncDstAlpha: @(GL_ZERO),
		}];
		
		_shadowClearRenderState = [CCRenderState renderStateWithBlendMode:shadowClearBlend shader:[CCShader positionColorShader] mainTexture:[CCTexture none]];
		
		CCBlendMode *lightBlend = [CCBlendMode blendModeWithOptions:@{
			CCBlendEquationColor: @(GL_FUNC_ADD),
			CCBlendFuncSrcColor: @(GL_DST_ALPHA),
			CCBlendFuncDstColor: @(GL_ONE),
		}];
		
		CCTexture *lightTexture = [CCTexture textureWithFile:@"LightAttenuation.psd"];
		_lightRenderState = [CCRenderState renderStateWithBlendMode:lightBlend shader:[CCShader positionTextureColorShader] mainTexture:lightTexture];
	}
	
	return self;
}

-(void)onEnter
{
	// This is a private director method and is crummy way of aligning the lightmap with the screen.
	// A better (and simpler) solution in hindsight would be to share the screen's projection with the render texture and
	// use an identity transform when rendering to the screen. 
	CGRect viewport = [CCDirector sharedDirector].viewportRect;
	_lightMapBuffer = [CCRenderTexture renderTextureWithWidth:ceilf(viewport.size.width) height:ceilf(viewport.size.height)];
	_lightMapBuffer.position = viewport.origin;
	_lightMapBuffer.contentScale /= 2;
	
	// This is currently a private method. CCRenderTextures default to being "aliased" (nearest neighbor filtering) for v2.x compatibility.
	// Will be making a proper method to set this up soon since this is not very texture cache friendly.
	[_lightMapBuffer.texture setTexParameters:&(ccTexParams){GL_LINEAR, GL_LINEAR, GL_CLAMP_TO_EDGE, GL_CLAMP_TO_EDGE}];
	
	_lightMapBuffer.projection = GLKMatrix4MakeOrtho(CGRectGetMinX(viewport), CGRectGetMaxX(viewport), CGRectGetMinY(viewport), CGRectGetMaxY(viewport), -1024, 1024);
	
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

static inline GLKVector2 GLKMatrix4MultiplyVector2(GLKMatrix4 m, GLKVector2 v){
	GLKVector4 v4 = GLKMatrix4MultiplyVector4(m, GLKVector4Make(v.x, v.y, 0.0f, 1.0f));
	return GLKVector2Make(v4.x, v4.y);
}

-(void)maskLight:(CCNode<Light> *)light renderer:(CCRenderer *)renderer lightPosition:(GLKVector4)lightPosition radius:(float)radius projection:(GLKMatrix4 *)projection
{
	for(CCNode<Occluder> *occluder in _occluders){
		GLKVector2 *verts = occluder.occluderVertexes;
		int count = occluder.occluderVertexCount;
		CGAffineTransform toLight = occluder.nodeToWorldTransform;
		
		GLKMatrix4 occluderMatrix = GLKMatrix4Make(
			 toLight.a,  toLight.b, 0.0f, 0.0f,
			 toLight.c,  toLight.d, 0.0f, 0.0f,
			      0.0f,       0.0f, 1.0f, 0.0f,
			toLight.tx, toLight.ty, 0.0f, 1.0f
		);
		
		GLKMatrix4 transform = GLKMatrix4Multiply(*projection, occluderMatrix);
		
		CCRenderBuffer buffer = [renderer enqueueTriangles:2*count andVertexes:4*count withState:_shadowRenderState globalSortOrder:0];
		
		for(int i=0, j=count-1; i<count; j=i, i++){
			GLKVector2 v1 = GLKMatrix4MultiplyVector2(transform, verts[i]);
			GLKVector2 v2 = GLKMatrix4MultiplyVector2(transform, verts[(i + 1)%count]);
			
			CCRenderBufferSetVertex(buffer, 4*i + 0, (CCVertex){lightPosition, v1, v2, {0.0f, 0.0f,  0.0f, radius}});
			CCRenderBufferSetVertex(buffer, 4*i + 1, (CCVertex){lightPosition, v1, v2, {1.0f, 0.0f,  0.0f, radius}});
			CCRenderBufferSetVertex(buffer, 4*i + 2, (CCVertex){lightPosition, v1, v2, {0.0f, 1.0f, -1.0f, radius}});
			CCRenderBufferSetVertex(buffer, 4*i + 3, (CCVertex){lightPosition, v1, v2, {1.0f, 1.0f,  1.0f, radius}});
			
			CCRenderBufferSetTriangle(buffer, 2*i + 0, 4*i + 0, 4*i + 1, 4*i + 2);
			CCRenderBufferSetTriangle(buffer, 2*i + 1, 4*i + 1, 4*i + 3, 4*i + 2);
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
	GLKMatrix4 projection = _lightMapBuffer.projection;
	
	float ambient = 0.2*0.5;
	CCRenderer *rtRenderer = [_lightMapBuffer beginWithClear:ambient g:ambient b:ambient a:1.0f];
		for(CCNode<Light> *light in _lights){
			CGPoint pos = light.position;
			float radius = light.lightRadius;
			GLKVector4 color4 = GLKVector4MultiplyScalar(light.lightColor, 0.5);
			
			CGPoint light2 = [light convertToWorldSpace:light.anchorPointInPoints];
			GLKVector4 lightPosition = GLKMatrix4MultiplyVector4(projection, GLKVector4Make(light2.x, light2.y, 0.0f, 1.0f));
			
			// Clear the alpha under the light.
			{
				const GLKVector2 zero2 = {{0.0f, 0.0f}};
				const GLKVector4 white = {{1.0f, 1.0f, 1.0f, 1.0f}};
				
				CCRenderBuffer buffer = [rtRenderer enqueueTriangles:2 andVertexes:4 withState:_shadowClearRenderState globalSortOrder:0];
				CCRenderBufferSetVertex(buffer, 0, LightVertex(projection, GLKVector2Make(pos.x - radius, pos.y - radius), zero2, white));
				CCRenderBufferSetVertex(buffer, 1, LightVertex(projection, GLKVector2Make(pos.x - radius, pos.y + radius), zero2, white));
				CCRenderBufferSetVertex(buffer, 2, LightVertex(projection, GLKVector2Make(pos.x + radius, pos.y + radius), zero2, white));
				CCRenderBufferSetVertex(buffer, 3, LightVertex(projection, GLKVector2Make(pos.x + radius, pos.y - radius), zero2, white));
				CCRenderBufferSetTriangle(buffer, 0, 0, 1, 2);
				CCRenderBufferSetTriangle(buffer, 1, 0, 2, 3);
			}
			
			// Draw the shadow mask.
			[self maskLight:light renderer:rtRenderer lightPosition:lightPosition radius:0.1 projection:&projection];
			
			// This is kind of a nasty hack...
			for(CCNode *occluder in _occluders){
				[occluder visit:rtRenderer parentTransform:&projection];
			}
			
			// Render a quad for the light.
			{
				CCRenderBuffer buffer = [rtRenderer enqueueTriangles:2 andVertexes:4 withState:_lightRenderState globalSortOrder:0];
				CCRenderBufferSetVertex(buffer, 0, LightVertex(projection, GLKVector2Make(pos.x - radius, pos.y - radius), GLKVector2Make(0, 0), color4));
				CCRenderBufferSetVertex(buffer, 1, LightVertex(projection, GLKVector2Make(pos.x - radius, pos.y + radius), GLKVector2Make(0, 1), color4));
				CCRenderBufferSetVertex(buffer, 2, LightVertex(projection, GLKVector2Make(pos.x + radius, pos.y + radius), GLKVector2Make(1, 1), color4));
				CCRenderBufferSetVertex(buffer, 3, LightVertex(projection, GLKVector2Make(pos.x + radius, pos.y - radius), GLKVector2Make(1, 0), color4));
				CCRenderBufferSetTriangle(buffer, 0, 0, 1, 2);
				CCRenderBufferSetTriangle(buffer, 1, 0, 2, 3);
			}
		}
	[_lightMapBuffer end];
	
	[super visit:renderer parentTransform:parentTransform];
}

@end
