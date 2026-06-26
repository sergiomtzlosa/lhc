//
//  LHCSimulationConfig.h
//  LHC Interactive
//
//  Central, persistable configuration for both the 3D model and the
//  stylised collision simulation.  Every control in the inspector writes
//  to this object; the scene and the particle factory read from it.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A collision "event" preset.  Presets are intentionally illustrative:
 they change the colour, density and energy of the particle burst so the
 visitor can compare the character of different LHC programmes.
 */
@interface LHCCollisionPreset : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *detail;
@property (nonatomic, copy, readonly) NSString *energyLabel;
@property (nonatomic, copy, readonly) NSArray<NSColor *> *palette;
@property (nonatomic, readonly) CGFloat countMultiplier;
@property (nonatomic, readonly) CGFloat velocityMultiplier;

+ (NSArray<LHCCollisionPreset *> *)presets;

@end

/**
 The live configuration shared by the inspector, the procedural model and
 the particle effect factory.  Values are clamped on read and persisted in
 NSUserDefaults so the installation remembers its last state.
 */
@interface LHCSimulationConfig : NSObject

// Beam
@property (nonatomic) CGFloat beamSpeed;             // 0.2 ... 2.5 orbit speed multiplier
@property (nonatomic) NSInteger beamParticleCount;   // 1 ... 8 visible tracers per beam
@property (nonatomic) CGFloat beamEnergyTeV;         // 0.45 ... 7.0 TeV per beam
@property (nonatomic, copy) NSString *collisionDetectorIdentifier;

// Collision particle simulation
@property (nonatomic) NSInteger collisionPresetIndex;
@property (nonatomic) NSInteger particleCount;       // 120 ... 3000
@property (nonatomic) CGFloat particleLifetime;      // seconds
@property (nonatomic) CGFloat particleVelocity;      // SceneKit units / s
@property (nonatomic) CGFloat particleSpread;        // degrees
@property (nonatomic) CGFloat particleSize;          // SceneKit units

// Model configuration
@property (nonatomic) BOOL showTerrain;
@property (nonatomic) BOOL showTunnel;
@property (nonatomic) BOOL showMagnets;
@property (nonatomic) BOOL showDetectors;
@property (nonatomic) BOOL showLabels;
@property (nonatomic) BOOL cutawayView;
@property (nonatomic) CGFloat tunnelOpacity;         // 0.08 ... 0.85
@property (nonatomic) CGFloat detectorScale;         // 0.7 ... 1.4

@property (nonatomic, readonly) LHCCollisionPreset *collisionPreset;
@property (nonatomic, readonly) NSInteger effectiveParticleCount;
@property (nonatomic, readonly) CGFloat collisionEnergyTeV;

- (void)loadFromUserDefaults;
- (void)saveToUserDefaults;
- (void)resetModelOptions;
- (void)resetCollisionOptions;

@end

NS_ASSUME_NONNULL_END
