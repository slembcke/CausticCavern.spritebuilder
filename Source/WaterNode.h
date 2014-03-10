#import <Foundation/Foundation.h>
#import "cocos2d.h"

@interface WaterNode : CCSprite

-(void)applyBuoyancy:(CCPhysicsCollisionPair *)pair;

@end
