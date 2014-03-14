//
//  MainScene.m
//  PROJECTNAME
//
//  Created by Viktor on 10/10/13.
//  Copyright (c) 2013 Apportable. All rights reserved.
//

#import "CCPhysics+ObjectiveChipmunk.h"
#import "CCTexture_Private.h"
#import "CCTextureCache.h"

#import "MainScene.h"
#import "WaterNode.h"
#import "LightingLayer.h"


@implementation MainScene {
	CCSprite *_backgroundSprite;
	CCPhysicsNode *_physicsNode;
	LightingLayer *_lightingLayer;
}

-(void)onEnter
{
	CCTexture *caustics = [[CCTextureCache sharedTextureCache] addImage:@"Caustics.psd"];
	caustics.texParameters = &((ccTexParams){GL_LINEAR, GL_LINEAR, GL_REPEAT, GL_REPEAT});
	
	_backgroundSprite.shaderUniforms[@"caustics"] = caustics;
	_backgroundSprite.shaderUniforms[@"causticsSize"] = [NSValue valueWithCGSize:CC_SIZE_SCALE(caustics.contentSize, 4.0)];
	
	_backgroundSprite.shader = [[CCShader alloc] initWithVertexShaderSource:CC_GLSL(
		uniform vec2 causticsSize;
		
		varying highp vec2 causticsCoord1;
		varying highp vec2 causticsCoord2;
		
		void main(){
			gl_Position = cc_Position;
			cc_FragTexCoord1 = cc_TexCoord1;
			cc_FragColor = cc_Color;
			
			const float f = 1.0;
			
			vec4 offset1 = mod(cc_Time[0]*vec4(16.0, -11.0, 0.0, 0.0), vec4(causticsSize, 1.0, 1.0));
			causticsCoord1 = (cc_ProjectionInv*cc_Position + offset1).xy/causticsSize;
			
			vec4 offset2 = mod(cc_Time[0]*vec4(-14.0, -7.0, 0.0, 0.0), vec4(causticsSize, 1.0, 1.0));
			causticsCoord2 = (cc_ProjectionInv*cc_Position + offset2).xy/causticsSize;
		}
	) fragmentShaderSource:CC_GLSL(
		uniform sampler2D caustics;
		
		varying highp vec2 causticsCoord1;
		varying highp vec2 causticsCoord2;
		
		void main(){
			vec4 bg = texture2D(cc_MainTexture, cc_FragTexCoord1)*cc_FragColor;
			vec4 caustics1 = texture2D(caustics, causticsCoord1);
			vec4 caustics2 = texture2D(caustics, causticsCoord2);
			gl_FragColor = bg + 0.2*(caustics1 + caustics2);
		}
	)];
	
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
		const GLKVector4 zero4 = {{0, 0, 0, 0}};
		
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
