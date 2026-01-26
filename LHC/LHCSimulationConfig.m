//
//  LHCSimulationConfig.m
//  LHC Interactive
//

#import "LHCSimulationConfig.h"

static NSString *const LHCDefaultsKey = @"org.cern.lhc.interactive.configuration.v1";

static inline CGFloat LHCClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return MIN(MAX(value, minimum), maximum);
}

#pragma mark - Collision preset

@interface LHCCollisionPreset ()
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *detail;
@property (nonatomic, copy, readwrite) NSString *energyLabel;
@property (nonatomic, copy, readwrite) NSArray<NSColor *> *palette;
@property (nonatomic, readwrite) CGFloat countMultiplier;
@property (nonatomic, readwrite) CGFloat velocityMultiplier;
@end

@implementation LHCCollisionPreset

+ (instancetype)presetNamed:(NSString *)name
                     detail:(NSString *)detail
                energyLabel:(NSString *)energyLabel
                    palette:(NSArray<NSColor *> *)palette
           countMultiplier:(CGFloat)countMultiplier
        velocityMultiplier:(CGFloat)velocityMultiplier {
    LHCCollisionPreset *preset = [[self alloc] init];
    preset.name = name;
    preset.detail = detail;
    preset.energyLabel = energyLabel;
    preset.palette = palette;
    preset.countMultiplier = countMultiplier;
    preset.velocityMultiplier = velocityMultiplier;
    return preset;
}

+ (NSArray<LHCCollisionPreset *> *)presets {
    static NSArray<LHCCollisionPreset *> *presets;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        presets = @[
            [self presetNamed:@"Proton–proton · 13.6 TeV"
                       detail:@"General-purpose pp collisions. A busy, multi-coloured spray of charged particles and neutral energy."
                  energyLabel:@"√s = 13.6 TeV"
                      palette:@[
                          [NSColor colorWithSRGBRed:0.20 green:0.82 blue:1.00 alpha:1.0],
                          [NSColor colorWithSRGBRed:1.00 green:0.82 blue:0.34 alpha:1.0],
                          [NSColor colorWithSRGBRed:1.00 green:0.36 blue:0.72 alpha:1.0],
                          [NSColor colorWithSRGBRed:0.92 green:0.95 blue:1.00 alpha:1.0]
                      ]
              countMultiplier:1.0 velocityMultiplier:1.0],
            [self presetNamed:@"Higgs → γγ · 125 GeV"
                       detail:@"A rare Higgs-boson event reconstructed from two high-energy photons. Fewer, brighter, high-pT tracks."
                  energyLabel:@"mH = 125 GeV"
                      palette:@[
                          [NSColor colorWithSRGBRed:1.00 green:0.92 blue:0.48 alpha:1.0],
                          [NSColor colorWithSRGBRed:1.00 green:1.00 blue:1.00 alpha:1.0],
                          [NSColor colorWithSRGBRed:0.55 green:0.88 blue:1.00 alpha:1.0]
                      ]
              countMultiplier:0.62 velocityMultiplier:1.35],
            [self presetNamed:@"Lead–lead · 5.02 TeV"
                       detail:@"Heavy-ion collisions melt protons and neutrons into a quark–gluon plasma. Dense, hot, orange-red debris."
                  energyLabel:@"√sNN = 5.02 TeV"
                      palette:@[
                          [NSColor colorWithSRGBRed:1.00 green:0.38 blue:0.16 alpha:1.0],
                          [NSColor colorWithSRGBRed:1.00 green:0.65 blue:0.20 alpha:1.0],
                          [NSColor colorWithSRGBRed:1.00 green:0.22 blue:0.44 alpha:1.0]
                      ]
              countMultiplier:1.75 velocityMultiplier:0.75],
            [self presetNamed:@"Beauty physics · LHCb"
                       detail:@"A forward beauty-hadron decay. Long-lived particles travel a measurable distance before decaying."
                  energyLabel:@"b-hadron event"
                      palette:@[
                          [NSColor colorWithSRGBRed:0.32 green:0.94 blue:0.68 alpha:1.0],
                          [NSColor colorWithSRGBRed:0.30 green:0.72 blue:1.00 alpha:1.0],
                          [NSColor colorWithSRGBRed:0.88 green:1.00 blue:0.92 alpha:1.0]
                      ]
              countMultiplier:0.78 velocityMultiplier:0.95]
        ];
    });
    return presets;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<LHCCollisionPreset: %@>", self.name];
}

@end

#pragma mark - Configuration

@implementation LHCSimulationConfig {
    NSUserDefaults *_defaults;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _defaults = [NSUserDefaults standardUserDefaults];
        [self applyFactoryDefaults];
        [self loadFromUserDefaults];
    }
    return self;
}

- (void)applyFactoryDefaults {
    _beamSpeed = 1.0;
    _beamParticleCount = 1;
    _beamEnergyTeV = 6.8;
    _collisionDetectorIdentifier = @"atlas";
    _collisionPresetIndex = 0;
    _particleCount = 720;
    _particleLifetime = 1.8;
    _particleVelocity = 7.0;
    _particleSpread = 180.0;
    _particleSize = 0.085;

    _showTerrain = YES;
    _showTunnel = YES;
    _showMagnets = YES;
    _showDetectors = YES;
    _showLabels = YES;
    _cutawayView = NO;
    _tunnelOpacity = 0.34;
    _detectorScale = 1.0;
}

- (void)loadFromUserDefaults {
    // A dictionary keeps the stored configuration namespaced and versioned.
    NSDictionary *stored = [_defaults dictionaryForKey:LHCDefaultsKey];
    if (![stored isKindOfClass:[NSDictionary class]]) {
        return;
    }

    NSNumber *(^number)(NSString *) = ^NSNumber *(NSString *key) {
        id value = stored[key];
        return [value isKindOfClass:[NSNumber class]] ? value : nil;
    };

    if (number(@"beamSpeed") != nil) _beamSpeed = number(@"beamSpeed").doubleValue;
    if (number(@"beamParticleCount") != nil) _beamParticleCount = number(@"beamParticleCount").integerValue;
    if (number(@"beamEnergyTeV") != nil) _beamEnergyTeV = number(@"beamEnergyTeV").doubleValue;
    if (number(@"collisionPresetIndex") != nil) _collisionPresetIndex = number(@"collisionPresetIndex").integerValue;
    if (number(@"particleCount") != nil) _particleCount = number(@"particleCount").integerValue;
    if (number(@"particleLifetime") != nil) _particleLifetime = number(@"particleLifetime").doubleValue;
    if (number(@"particleVelocity") != nil) _particleVelocity = number(@"particleVelocity").doubleValue;
    if (number(@"particleSpread") != nil) _particleSpread = number(@"particleSpread").doubleValue;
    if (number(@"particleSize") != nil) _particleSize = number(@"particleSize").doubleValue;
    if (number(@"tunnelOpacity") != nil) _tunnelOpacity = number(@"tunnelOpacity").doubleValue;
    if (number(@"detectorScale") != nil) _detectorScale = number(@"detectorScale").doubleValue;

    if (number(@"showTerrain") != nil) _showTerrain = number(@"showTerrain").boolValue;
    if (number(@"showTunnel") != nil) _showTunnel = number(@"showTunnel").boolValue;
    if (number(@"showMagnets") != nil) _showMagnets = number(@"showMagnets").boolValue;
    if (number(@"showDetectors") != nil) _showDetectors = number(@"showDetectors").boolValue;
    if (number(@"showLabels") != nil) _showLabels = number(@"showLabels").boolValue;
    if (number(@"cutawayView") != nil) _cutawayView = number(@"cutawayView").boolValue;

    id detector = stored[@"collisionDetectorIdentifier"];
    if ([detector isKindOfClass:[NSString class]] && [detector length] > 0) {
        _collisionDetectorIdentifier = [detector copy];
    }

    [self clampAllValues];
}

- (void)saveToUserDefaults {
    [self clampAllValues];
    NSDictionary *stored = @{
        @"beamSpeed": @(_beamSpeed),
        @"beamParticleCount": @(_beamParticleCount),
        @"beamEnergyTeV": @(_beamEnergyTeV),
        @"collisionDetectorIdentifier": _collisionDetectorIdentifier ?: @"atlas",
        @"collisionPresetIndex": @(_collisionPresetIndex),
        @"particleCount": @(_particleCount),
        @"particleLifetime": @(_particleLifetime),
        @"particleVelocity": @(_particleVelocity),
        @"particleSpread": @(_particleSpread),
        @"particleSize": @(_particleSize),
        @"showTerrain": @(_showTerrain),
        @"showTunnel": @(_showTunnel),
        @"showMagnets": @(_showMagnets),
        @"showDetectors": @(_showDetectors),
        @"showLabels": @(_showLabels),
        @"cutawayView": @(_cutawayView),
        @"tunnelOpacity": @(_tunnelOpacity),
        @"detectorScale": @(_detectorScale)
    };
    [_defaults setObject:stored forKey:LHCDefaultsKey];
}

- (void)clampAllValues {
    _beamSpeed = LHCClamp(_beamSpeed, 0.2, 2.5);
    _beamParticleCount = (NSInteger)LHCClamp((CGFloat)_beamParticleCount, 1.0, 8.0);
    _beamEnergyTeV = LHCClamp(_beamEnergyTeV, 0.45, 7.0);
    _particleCount = (NSInteger)LHCClamp((CGFloat)_particleCount, 120.0, 3000.0);
    _particleLifetime = LHCClamp(_particleLifetime, 0.5, 4.0);
    _particleVelocity = LHCClamp(_particleVelocity, 1.0, 20.0);
    _particleSpread = LHCClamp(_particleSpread, 20.0, 180.0);
    _particleSize = LHCClamp(_particleSize, 0.02, 0.35);
    _tunnelOpacity = LHCClamp(_tunnelOpacity, 0.08, 0.85);
    _detectorScale = LHCClamp(_detectorScale, 0.70, 1.40);

    NSInteger presetCount = (NSInteger)[[LHCCollisionPreset presets] count];
    _collisionPresetIndex = (NSInteger)LHCClamp((CGFloat)_collisionPresetIndex, 0.0, (CGFloat)(presetCount - 1));
}

- (LHCCollisionPreset *)collisionPreset {
    NSArray *presets = [LHCCollisionPreset presets];
    NSInteger index = MIN(MAX(self.collisionPresetIndex, 0), (NSInteger)presets.count - 1);
    return presets[index];
}

- (NSInteger)effectiveParticleCount {
    return (NSInteger)round((CGFloat)self.particleCount * self.collisionPreset.countMultiplier);
}

- (CGFloat)collisionEnergyTeV {
    return self.beamEnergyTeV * 2.0;
}

- (void)resetModelOptions {
    _showTerrain = YES;
    _showTunnel = YES;
    _showMagnets = YES;
    _showDetectors = YES;
    _showLabels = YES;
    _cutawayView = NO;
    _tunnelOpacity = 0.34;
    _detectorScale = 1.0;
    [self saveToUserDefaults];
}

- (void)resetCollisionOptions {
    _collisionPresetIndex = 0;
    _particleCount = 720;
    _particleLifetime = 1.8;
    _particleVelocity = 7.0;
    _particleSpread = 180.0;
    _particleSize = 0.085;
    [self saveToUserDefaults];
}

@end
