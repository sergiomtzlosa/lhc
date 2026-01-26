//
//  LHCParticleSystemFactory.h
//  LHC Interactive
//
//  Builds the stylised, fully configurable collision effect: glowing
//  particle showers, radiating track segments, shock-wave shells and a
//  brief flash light.  Also provides the visual for an incoming bunch.
//

#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>
#import "LHCSimulationConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface LHCParticleSystemFactory : NSObject

/// A compact, emissive swarm used when two bunches are brought together.
+ (SCNNode *)incomingBunchClusterWithColor:(NSColor *)color;

/// A self-animating effect node. Add it to the scene at the collision point.
+ (SCNNode *)collisionEffectWithPreset:(LHCCollisionPreset *)preset
                               config:(LHCSimulationConfig *)config;

/// How long the caller should keep the effect node in the scene.
+ (NSTimeInterval)suggestedEffectDurationForConfig:(LHCSimulationConfig *)config;

/// A soft radial sprite shared by beams and particles.
+ (NSImage *)glowSprite;

@end

NS_ASSUME_NONNULL_END
