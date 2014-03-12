//
//  MainScene.m
//  PROJECTNAME
//
//  Created by Viktor on 10/10/13.
//  Copyright (c) 2013 Apportable. All rights reserved.
//

#import "CCPhysics+ObjectiveChipmunk.h"

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


@protocol Occluder

@property(nonatomic, readonly) CCVertex *occluderVertexes;
@property(nonatomic, readonly) int occluderVertexCount;

@end


@interface LightingLayer : CCNode @end
@implementation LightingLayer {
	NSMutableArray *_occluders;
}

-(id)init
{
	if((self = [super init])){
		_occluders = [NSMutableArray array];
	}
	
	return self;
}

-(LightingLayer *)lightingLayer
{
	return self;
}

-(void)addOccluder:(CCNode<Occluder> *)occluder
{
	[_occluders addObject:occluder];
}

-(void)removeOccluder:(CCNode<Occluder> *)occluder
{
	[_occluders removeObject:occluder];
}

-(void)draw:(CCRenderer *)renderer transform:(const GLKMatrix4 *)modelViewProjection
{
	GLKMatrix4 projection = [CCDirector sharedDirector].projectionMatrix;
	GLKMatrix4 projectionInv = GLKMatrix4Invert(projection, NULL);
	GLKMatrix4 modelView = GLKMatrix4Multiply(projectionInv, *modelViewProjection);
	
	CGAffineTransform worldToLight = self.worldToNodeTransform;
	CCRenderState *renderState = [CCRenderState debugColor];
	
	for(CCNode<Occluder> *occluder in _occluders){
		CCVertex *verts = occluder.occluderVertexes;
		int count = occluder.occluderVertexCount;
		CGAffineTransform toLight = CGAffineTransformConcat(occluder.nodeToWorldTransform, worldToLight);
		
		GLKMatrix4 occluderMatrix = GLKMatrix4Multiply(modelView, GLKMatrix4Make(
			 toLight.a,  toLight.b, 0.0f, 0.0f,
			 toLight.c,  toLight.d, 0.0f, 0.0f,
			      0.0f,       0.0f, 1.0f, 0.0f,
			toLight.tx, toLight.ty, 0.0f, 1.0f
		));
		
		float lx = 100.0f, ly = 100.0f;
		GLKMatrix4 shadowMatrix = GLKMatrix4Multiply(GLKMatrix4Make(
			1.0f, 0.0f, 0.0f,  0.0f,
			0.0f, 1.0f, 0.0f,  0.0f,
			 -lx,   ly, 0.0f, -1.0f,
			0.0f, 0.0f, 0.0f,  1.0f
		), occluderMatrix);
		
		GLKMatrix4 shadowProjection = GLKMatrix4Multiply(projection, shadowMatrix);
		
		CCRenderBuffer debug = [renderer enqueueLines:2*count andVertexes:2*count withState:renderState];
		
		for(int i=0; i<count; i++){
			CCVertex v = verts[i];
			CCRenderBufferSetVertex(debug, 2*i + 0, CCVertexApplyTransform(v, &shadowProjection));
			
			v.position.z = 1.0;
			CCRenderBufferSetVertex(debug, 2*i + 1, CCVertexApplyTransform(v, &shadowProjection));
			
			CCRenderBufferSetLine(debug, 2*i + 0, 2*i, 2*((i + 1)%count));
			CCRenderBufferSetLine(debug, 2*i + 1, 2*i, 2*i + 1);
		}
	}
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
		const GLKVector2 zero = {{0, 0}};
		const GLKVector4 red = {{1, 0, 0, 1}};
		
		_occluderVertexes[i] = (CCVertex){GLKVector4Make(v.x, v.y, 0.0f, 1.0f), zero, zero, red};
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
