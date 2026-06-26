//
//  LHCParticleSystemFactory.m
//  LHC Interactive
//

#import "LHCParticleSystemFactory.h"
#import <simd/simd.h>

static const simd_float3 LHCUpVector = {0.0f, 1.0f, 0.0f};

static SCNMaterial *LHCAdditiveMaterial(NSColor *color, CGFloat intensity) {
    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelConstant;
    // Keep a small diffuse contribution: SceneKit can drop an emissive-only
    // material when its diffuse alpha is fully transparent.
    material.diffuse.contents = [color colorWithAlphaComponent:0.32];
    material.emission.contents = color;
    material.emission.intensity = intensity;
    material.blendMode = SCNBlendModeAdd;
    material.writesToDepthBuffer = NO;
    material.readsFromDepthBuffer = NO;
    material.doubleSided = YES;
    material.transparency = 1.0;
    return material;
}

static simd_float3 LHCRandomUnitVector(void) {
    CGFloat z = ((CGFloat)arc4random_uniform(20000) / 10000.0) - 1.0;
    CGFloat angle = ((CGFloat)arc4random_uniform(20000) / 10000.0) * (CGFloat)M_PI;
    CGFloat radius = sqrt(MAX(0.0, 1.0 - z * z));
    return simd_normalize(simd_make_float3(cosf((float)angle) * (float)radius,
                                           (float)z,
                                           sinf((float)angle) * (float)radius));
}

@implementation LHCParticleSystemFactory

#pragma mark - Shared sprites

+ (NSImage *)glowSprite {
    static NSImage *sprite;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const CGFloat side = 256.0;
        sprite = [NSImage imageWithSize:NSMakeSize(side, side)
                                flipped:NO
                         drawingHandler:^BOOL(NSRect rect) {
            NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
                [NSColor colorWithCalibratedWhite:1.0 alpha:1.0],
                [NSColor colorWithCalibratedWhite:1.0 alpha:0.94],
                [NSColor colorWithCalibratedWhite:1.0 alpha:0.62],
                [NSColor colorWithCalibratedWhite:1.0 alpha:0.18],
                [NSColor colorWithCalibratedWhite:1.0 alpha:0.0]
            ]];
            [gradient drawInRect:NSInsetRect(rect, 6, 6)
          relativeCenterPosition:NSZeroPoint];
            return YES;
        }];
    });
    return sprite;
}

#pragma mark - Particle systems

+ (SCNParticleSystem *)particleSystemWithColor:(NSColor *)color
                                        config:(LHCSimulationConfig *)config
                                        preset:(LHCCollisionPreset *)preset
                                         count:(NSInteger)count
                                velocityFactor:(CGFloat)velocityFactor
                                    sizeFactor:(CGFloat)sizeFactor
                                    lifeFactor:(CGFloat)lifeFactor
                                stretchFactor:(CGFloat)stretchFactor
                              emittingDirection:(SCNVector3)direction
                                   spreadAngle:(CGFloat)spreadAngle {
    SCNParticleSystem *system = [SCNParticleSystem particleSystem];

    // SceneKit interprets birthRate as particles per second. A compact
    // emission window turns that into a single expanding event.
    system.emissionDuration = 0.075;
    system.emissionDurationVariation = 0.025;
    system.loops = NO;
    system.birthRate = MAX(30.0, (CGFloat)count / system.emissionDuration);

    system.particleLifeSpan = config.particleLifetime * lifeFactor;
    system.particleLifeSpanVariation = config.particleLifetime * lifeFactor * 0.42;
    system.particleVelocity = config.particleVelocity * preset.velocityMultiplier * velocityFactor;
    system.particleVelocityVariation = config.particleVelocity * 0.46;
    system.particleSize = config.particleSize * sizeFactor;
    system.particleSizeVariation = config.particleSize * sizeFactor * 0.62;

    system.birthDirection = SCNParticleBirthDirectionConstant;
    system.emittingDirection = direction;
    system.spreadingAngle = spreadAngle;

    system.acceleration = SCNVector3Make(0, -0.48, 0);
    system.dampingFactor = 0.28;
    system.particleMass = 0.020;
    system.particleBounce = 0.0;
    system.affectedByGravity = NO;
    system.affectedByPhysicsFields = NO;
    system.particleDiesOnCollision = NO;

    system.particleImage = [self glowSprite];
    system.particleColor = color;
    system.particleColorVariation = SCNVector4Make(0.09, 0.06, 0.12, 0.0);
    system.particleIntensity = 2.25;
    system.particleIntensityVariation = 0.9;
    system.blendMode = SCNParticleBlendModeAdditive;
    system.orientationMode = SCNParticleOrientationModeBillboardScreenAligned;
    system.sortingMode = SCNParticleSortingModeDistance;
    system.lightingEnabled = NO;
    system.writesToDepthBuffer = NO;
    system.stretchFactor = stretchFactor;
    system.fresnelExponent = 1.4;
    return system;
}

#pragma mark - Tracks

+ (SCNNode *)eventTrackWithDirection:(simd_float3)direction
                              length:(CGFloat)length
                               color:(NSColor *)color
                             opacity:(CGFloat)opacity {
    SCNNode *track = [SCNNode node];
    track.name = @"collision.track";
    track.renderingOrder = 90;

    NSInteger segmentCount = 5;
    CGFloat segmentLength = length / (CGFloat)segmentCount;
    simd_float3 point = simd_make_float3(0, 0, 0);
    simd_float3 tangent = simd_normalize(direction);
    SCNMaterial *material = LHCAdditiveMaterial(color, 3.6);
    material.transparency = opacity;

    // A tiny random bend models the effect of the detector's magnetic field.
    CGFloat curlDirection = (arc4random_uniform(2) == 0) ? 1.0 : -1.0;
    for (NSInteger i = 0; i < segmentCount; i++) {
        simd_float3 next = point + tangent * (float)segmentLength;
        simd_float3 bendAxis = simd_cross(tangent, LHCUpVector);
        if (simd_length(bendAxis) < 0.02f) {
            bendAxis = simd_make_float3(1, 0, 0);
        }
        bendAxis = simd_normalize(bendAxis);
        tangent = simd_normalize(tangent + bendAxis * (float)(0.24 * curlDirection)
                                 + simd_make_float3(0, -0.018f, 0));
        if (simd_length(next - point) < 0.001f) {
            break;
        }

        SCNCylinder *segment = [SCNCylinder cylinderWithRadius:
            (i == segmentCount - 1 ? 0.0050 : 0.0100)
                                                       height:simd_length(next - point)];
        segment.radialSegmentCount = 8;
        segment.heightSegmentCount = 1;
        segment.materials = @[material];

        SCNNode *segmentNode = [SCNNode nodeWithGeometry:segment];
        segmentNode.renderingOrder = 90;
        segmentNode.position = SCNVector3Make((point.x + next.x) * 0.5f,
                                              (point.y + next.y) * 0.5f,
                                              (point.z + next.z) * 0.5f);
        segmentNode.simdOrientation = simd_quaternion(LHCUpVector,
                                                       simd_normalize(next - point));
        [track addChildNode:segmentNode];
        point = next;
    }

    return track;
}

#pragma mark - Collision effect

+ (SCNNode *)collisionEffectWithPreset:(LHCCollisionPreset *)preset
                               config:(LHCSimulationConfig *)config {
    SCNNode *root = [SCNNode node];
    root.name = @"collision.effect";
    root.renderingOrder = 80;

    NSArray<NSColor *> *palette = preset.palette;
    NSInteger total = MAX(100, config.effectiveParticleCount);
    NSInteger perColor = MAX(24, total / MAX(1, (NSInteger)palette.count));

    NSColor *primary = palette.firstObject ?: [NSColor whiteColor];
    NSColor *secondary = palette.count > 1 ? palette[1] : primary;

    // 1. Incandescent core and expanding light shell.
    SCNMaterial *coreMaterial = LHCAdditiveMaterial([NSColor colorWithSRGBRed:0.92 green:0.98 blue:1.0 alpha:1.0], 4.0);
    SCNSphere *coreGeometry = [SCNSphere sphereWithRadius:0.11];
    coreGeometry.segmentCount = 32;
    coreGeometry.materials = @[coreMaterial];
    SCNNode *core = [SCNNode nodeWithGeometry:coreGeometry];
    core.renderingOrder = 95;
    core.scale = SCNVector3Make(0.22, 0.22, 0.22);
    [root addChildNode:core];
    [core runAction:[SCNAction sequence:@[
        [SCNAction group:@[[SCNAction scaleTo:1.5 duration:0.16],
                           [SCNAction fadeOutWithDuration:0.34]]]
    ]]];

    SCNMaterial *shellMaterial = LHCAdditiveMaterial(primary, 1.5);
    shellMaterial.transparency = 0.20;
    SCNSphere *shellGeometry = [SCNSphere sphereWithRadius:0.18];
    shellGeometry.segmentCount = 28;
    shellGeometry.materials = @[shellMaterial];
    SCNNode *lightShell = [SCNNode nodeWithGeometry:shellGeometry];
    lightShell.renderingOrder = 94;
    lightShell.scale = SCNVector3Make(0.2, 0.2, 0.2);
    [root addChildNode:lightShell];
    [lightShell runAction:[SCNAction sequence:@[
        [SCNAction group:@[[SCNAction scaleTo:2.8 duration:0.42],
                           [SCNAction fadeOutWithDuration:0.50]]]
    ]]];

    // A persistent soft halo reads as the collision's afterglow. It remains
    // visible through the detector so the event has a clear centre of mass.
    SCNPlane *afterglowPlane = [SCNPlane planeWithWidth:1.20 height:1.20];
    SCNMaterial *afterglowMaterial = LHCAdditiveMaterial(primary, 0.65);
    afterglowMaterial.diffuse.contents = [self glowSprite];
    afterglowMaterial.emission.contents = [self glowSprite];
    afterglowMaterial.transparency = 0.055;
    afterglowPlane.materials = @[afterglowMaterial];
    SCNNode *afterglow = [SCNNode nodeWithGeometry:afterglowPlane];
    afterglow.renderingOrder = 86;
    SCNBillboardConstraint *afterglowBillboard = [SCNBillboardConstraint billboardConstraint];
    afterglowBillboard.freeAxes = SCNBillboardAxisAll;
    afterglow.constraints = @[afterglowBillboard];
    afterglow.scale = SCNVector3Make(0.16, 0.16, 0.16);
    afterglow.opacity = 0.0;
    [root addChildNode:afterglow];
    [afterglow runAction:[SCNAction sequence:@[
        [SCNAction fadeInWithDuration:0.09],
        [SCNAction group:@[[SCNAction scaleTo:0.92 duration:0.50],
                           [SCNAction waitForDuration:0.52]]],
        [SCNAction fadeOutWithDuration:0.78]
    ]]];

    // 2. Two restrained shock-wave rings: one in the beam plane and one
    // transverse. They frame the burst without turning into a light show.
    NSArray<NSValue *> *ringOrientations = @[
        [NSValue valueWithSCNVector3:SCNVector3Make(0, 0, 0)],
        [NSValue valueWithSCNVector3:SCNVector3Make(M_PI_2, 0, 0)]
    ];
    for (NSInteger i = 0; i < 2; i++) {
        NSColor *ringColor = palette[i == 0 ? 0 : MIN((NSUInteger)2, palette.count - 1)];
        SCNMaterial *ringMaterial = LHCAdditiveMaterial(ringColor, 1.20);
        ringMaterial.transparency = 0.28;
        SCNTorus *ring = [SCNTorus torusWithRingRadius:1.0 pipeRadius:0.010];
        ring.ringSegmentCount = 160;
        ring.pipeSegmentCount = 10;
        ring.materials = @[ringMaterial];

        SCNNode *ringNode = [SCNNode nodeWithGeometry:ring];
        ringNode.renderingOrder = 88;
        ringNode.eulerAngles = ringOrientations[i].SCNVector3Value;
        ringNode.scale = SCNVector3Make(0.12, 0.12, 0.12);
        ringNode.opacity = 0.0;
        [root addChildNode:ringNode];

        NSTimeInterval delay = 0.015 + 0.06 * i;
        SCNAction *wait = [SCNAction waitForDuration:delay];
        SCNAction *appear = [SCNAction fadeInWithDuration:0.05];
        SCNAction *scale = [SCNAction scaleTo:1.70 + (CGFloat)i * 0.15 duration:0.55 + (CGFloat)i * 0.06];
        scale.timingMode = SCNActionTimingModeEaseOut;
        SCNAction *hold = [SCNAction waitForDuration:0.06];
        SCNAction *fade = [SCNAction fadeOutWithDuration:0.46];
        fade.timingMode = SCNActionTimingModeEaseOut;
        [ringNode runAction:[SCNAction sequence:@[wait, appear, scale, hold, fade]]];
    }

    // 3. Plasma cloud: several colour populations with different energies.
    for (NSInteger i = 0; i < (NSInteger)palette.count; i++) {
        NSColor *color = palette[i];
        CGFloat velocityFactor = 0.58 + 0.16 * (CGFloat)i;
        SCNParticleSystem *system = [self particleSystemWithColor:color
                                                           config:config
                                                           preset:preset
                                                            count:MAX(30, perColor)
                                                   velocityFactor:velocityFactor
                                                       sizeFactor:1.15 + (CGFloat)i * 0.10
                                                       lifeFactor:0.92 - (CGFloat)i * 0.05
                                                    stretchFactor:0.0
                                                 emittingDirection:SCNVector3Make(0, 1, 0)
                                                      spreadAngle:180.0];
        [root addParticleSystem:system];
    }

    // 4. Fast high-pT sparks. These stay round: the reconstructed tracks below
    // provide the directional streaks without turning the burst into rain.
    NSInteger sparkCount = MAX(42, total / 7);
    SCNParticleSystem *sparks = [self particleSystemWithColor:[NSColor whiteColor]
                                                       config:config
                                                       preset:preset
                                                        count:sparkCount
                                               velocityFactor:2.05
                                                   sizeFactor:0.30
                                                   lifeFactor:0.58
                                                stretchFactor:0.0
                                             emittingDirection:SCNVector3Make(0, 1, 0)
                                                  spreadAngle:180.0];
    sparks.particleColorVariation = SCNVector4Make(0.10, 0.18, 0.22, 0.0);
    sparks.particleIntensity = 2.6;
    [root addParticleSystem:sparks];

    // 5. Slow, warm embers add weight and a longer tail to the burst.
    SCNParticleSystem *embers = [self particleSystemWithColor:secondary
                                                       config:config
                                                       preset:preset
                                                        count:MAX(36, total / 7)
                                               velocityFactor:0.44
                                                   sizeFactor:1.65
                                                   lifeFactor:1.25
                                                stretchFactor:0.0
                                             emittingDirection:SCNVector3Make(0, 1, 0)
                                                  spreadAngle:180.0];
    embers.acceleration = SCNVector3Make(0, -0.18, 0);
    embers.dampingFactor = 0.72;
    embers.particleIntensity = 1.5;
    [root addParticleSystem:embers];

    // 6. A handful of long-lived muon candidates.
    SCNParticleSystem *muons = [self particleSystemWithColor:[NSColor colorWithSRGBRed:0.70 green:0.92 blue:1.0 alpha:1.0]
                                                      config:config
                                                      preset:preset
                                                       count:MAX(12, total / 75)
                                              velocityFactor:2.8
                                                  sizeFactor:0.22
                                                  lifeFactor:1.65
                                               stretchFactor:0.0
                                            emittingDirection:SCNVector3Make(0, 1, 0)
                                                 spreadAngle:180.0];
    muons.particleIntensity = 2.5;
    muons.dampingFactor = 0.12;
    [root addParticleSystem:muons];

    // 7. Reconstructed event-display tracks form a few collimated jets plus
    // high-momentum muons. These are drawn additively through the detector so
    // the collision remains legible from any camera angle.
    NSInteger jetCount = 4 + (preset.countMultiplier > 1.2 ? 1 : 0);
    for (NSInteger jet = 0; jet < jetCount; jet++) {
        simd_float3 jetAxis = LHCRandomUnitVector();
        NSUInteger jetPaletteCount = MIN((NSUInteger)3, palette.count);
        NSColor *jetColor = palette[(NSUInteger)jet % MAX((NSUInteger)1, jetPaletteCount)];
        NSInteger trackCount = 5 + (NSInteger)(preset.countMultiplier * 2.0);
        for (NSInteger j = 0; j < trackCount; j++) {
            simd_float3 jitter = LHCRandomUnitVector() * 0.44f;
            simd_float3 direction = simd_normalize(jetAxis + jitter);
            CGFloat length = 1.05 + ((CGFloat)arc4random_uniform(1000) / 1000.0) * 2.65;
            SCNNode *track = [self eventTrackWithDirection:direction
                                                    length:length
                                                     color:jetColor
                                                   opacity:0.94];
            NSTimeInterval delay = 0.018 * (NSTimeInterval)(j % 7);
            SCNAction *wait = [SCNAction waitForDuration:delay];
            SCNAction *appear = [SCNAction fadeInWithDuration:0.07];
            SCNAction *hold = [SCNAction waitForDuration:MAX(0.12, config.particleLifetime * 0.56)];
            SCNAction *fade = [SCNAction fadeOutWithDuration:0.58];
            [track runAction:[SCNAction sequence:@[wait, appear, hold, fade]]];
            [root addChildNode:track];

            if (j % 2 == 0) {
                simd_float3 vertexPosition = direction * (float)(length * 0.58);
                SCNSphere *vertexSphere = [SCNSphere sphereWithRadius:0.022];
                vertexSphere.segmentCount = 16;
                vertexSphere.materials = @[LHCAdditiveMaterial([NSColor whiteColor], 3.2)];
                SCNNode *vertex = [SCNNode nodeWithGeometry:vertexSphere];
                vertex.position = SCNVector3Make(vertexPosition.x, vertexPosition.y, vertexPosition.z);
                vertex.renderingOrder = 91;
                vertex.opacity = 0.0;
                SCNAction *vWait = [SCNAction waitForDuration:delay + 0.10];
                SCNAction *vAppear = [SCNAction fadeInWithDuration:0.045];
                SCNAction *vHold = [SCNAction waitForDuration:0.11];
                SCNAction *vFade = [SCNAction fadeOutWithDuration:0.32];
                [vertex runAction:[SCNAction sequence:@[vWait, vAppear, vHold, vFade]]];
                [root addChildNode:vertex];
            }
        }
    }

    for (NSInteger i = 0; i < 4; i++) {
        simd_float3 direction = LHCRandomUnitVector();
        CGFloat length = 3.4 + (CGFloat)i * 0.36;
        SCNNode *muonTrack = [self eventTrackWithDirection:direction
                                                    length:length
                                                     color:[NSColor colorWithSRGBRed:0.72 green:0.95 blue:1.0 alpha:1.0]
                                                   opacity:0.88];
        muonTrack.renderingOrder = 92;
        SCNAction *wait = [SCNAction waitForDuration:0.02 * (NSTimeInterval)i];
        SCNAction *appear = [SCNAction fadeInWithDuration:0.06];
        SCNAction *hold = [SCNAction waitForDuration:MAX(0.25, config.particleLifetime * 0.75)];
        SCNAction *fade = [SCNAction fadeOutWithDuration:0.42];
        [muonTrack runAction:[SCNAction sequence:@[wait, appear, hold, fade]]];
        [root addChildNode:muonTrack];
    }

    // 8. Brief omni lights make the surrounding detector geometry flash with
    // the event. A cool core flash and warm secondary give the light depth.
    SCNLight *flashLight = [SCNLight light];
    flashLight.type = SCNLightTypeOmni;
    flashLight.color = [NSColor colorWithSRGBRed:0.78 green:0.92 blue:1.0 alpha:1.0];
    flashLight.intensity = 80.0;
    flashLight.attenuationStartDistance = 0.0;
    flashLight.attenuationEndDistance = 8.0;
    SCNNode *lightNode = [SCNNode node];
    lightNode.light = flashLight;
    [root addChildNode:lightNode];

    CABasicAnimation *lightFade = [CABasicAnimation animationWithKeyPath:@"light.intensity"];
    lightFade.fromValue = @80.0;
    lightFade.toValue = @0.0;
    lightFade.duration = 0.92;
    lightFade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    lightFade.fillMode = kCAFillModeForwards;
    lightFade.removedOnCompletion = NO;
    [lightNode addAnimation:lightFade forKey:@"collisionFlash"];

    SCNLight *warmLight = [SCNLight light];
    warmLight.type = SCNLightTypeOmni;
    warmLight.color = [NSColor colorWithSRGBRed:1.0 green:0.52 blue:0.24 alpha:1.0];
    warmLight.intensity = 30.0;
    warmLight.attenuationStartDistance = 0.0;
    warmLight.attenuationEndDistance = 6.0;
    SCNNode *warmNode = [SCNNode node];
    warmNode.light = warmLight;
    [root addChildNode:warmNode];

    CABasicAnimation *warmFade = [CABasicAnimation animationWithKeyPath:@"light.intensity"];
    warmFade.fromValue = @30.0;
    warmFade.toValue = @0.0;
    warmFade.duration = 0.62;
    warmFade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    warmFade.fillMode = kCAFillModeForwards;
    warmFade.removedOnCompletion = NO;
    [warmNode addAnimation:warmFade forKey:@"warmFlash"];

    return root;
}

+ (NSTimeInterval)suggestedEffectDurationForConfig:(LHCSimulationConfig *)config {
    return MAX(2.8, config.particleLifetime + 2.0);
}

#pragma mark - Incoming bunches

+ (SCNNode *)incomingBunchClusterWithColor:(NSColor *)color {
    SCNNode *cluster = [SCNNode node];
    cluster.renderingOrder = 70;

    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelConstant;
    material.diffuse.contents = color;
    material.emission.contents = color;
    material.emission.intensity = 3.8;
    material.writesToDepthBuffer = NO;
    material.readsFromDepthBuffer = NO;

    const NSInteger protonCount = 11;
    for (NSInteger i = 0; i < protonCount; i++) {
        SCNCapsule *proton = [SCNCapsule capsuleWithCapRadius:0.024 height:0.15];
        proton.radialSegmentCount = 12;
        proton.capSegmentCount = 6;
        proton.heightSegmentCount = 4;
        proton.materials = @[material];

        SCNNode *node = [SCNNode nodeWithGeometry:proton];
        node.eulerAngles = SCNVector3Make(0, 0, M_PI_2); // align capsule with X
        node.renderingOrder = 70;
        CGFloat spread = 0.075;
        node.position = SCNVector3Make(((CGFloat)i - 5.0) * 0.028,
                                       ((CGFloat)arc4random_uniform(100) / 100.0 - 0.5) * spread,
                                       ((CGFloat)arc4random_uniform(100) / 100.0 - 0.5) * spread);
        [cluster addChildNode:node];
    }

    // A soft halo so the swarm reads as a bright "bunch".
    SCNPlane *halo = [SCNPlane planeWithWidth:0.9 height:0.9];
    SCNMaterial *haloMaterial = LHCAdditiveMaterial(color, 2.0);
    haloMaterial.diffuse.contents = [self glowSprite];
    haloMaterial.emission.contents = [self glowSprite];
    haloMaterial.transparency = 0.62;
    halo.materials = @[haloMaterial];

    SCNNode *haloNode = [SCNNode nodeWithGeometry:halo];
    haloNode.renderingOrder = 69;
    SCNBillboardConstraint *billboard = [SCNBillboardConstraint billboardConstraint];
    billboard.freeAxes = SCNBillboardAxisAll;
    haloNode.constraints = @[billboard];
    [cluster addChildNode:haloNode];

    return cluster;
}

@end
