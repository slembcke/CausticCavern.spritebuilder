#import <Foundation/Foundation.h>
#import "cocos2d.h"

@protocol Light
@property(nonatomic, readonly) float lightRadius;
@property(nonatomic, readonly) GLKVector4 lightColor;
@end


@protocol Occluder
@property(nonatomic, readonly) CCVertex *occluderVertexes;
@property(nonatomic, readonly) int occluderVertexCount;
@end


@interface LightingLayer : CCNode

-(void)addLight:(CCNode<Light> *)light;
-(void)removeLight:(CCNode<Light> *)light;
-(void)addOccluder:(CCNode<Occluder> *)occluder;
-(void)removeOccluder:(CCNode<Occluder> *)occluder;

@end


@interface CCNode(LightingLayer)
-(LightingLayer *)lightingLayer;
@end
