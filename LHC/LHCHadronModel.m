//
//  LHCHadronModel.m
//  LHC Interactive
//

#import "LHCHadronModel.h"
#import "LHCParticleSystemFactory.h"
#import <SceneKit/SceneKit.h>

static const CGFloat LHCRingRadius = 9.6;
static const CGFloat LHCBeamHeight = 1.16;
static const CGFloat LHCBeamARadialOffset = -0.12;
static const CGFloat LHCBeamBRadialOffset = 0.12;
static const NSInteger LHCBeamTracerMaximum = 8;
static const CGFloat LHCSiteBaseY = -1.32;
static const CGFloat LHCSiteRoadInnerRadius = 14.15;
static const CGFloat LHCSiteRoadOuterRadius = 15.15;

static BOOL LHCEnvironmentFlagIsEnabled(NSString *name) {
    NSString *value = NSProcessInfo.processInfo.environment[name];
    if (value.length == 0) {
        return NO;
    }
    NSString *normalized = value.lowercaseString;
    return !([normalized isEqualToString:@"0"] ||
             [normalized isEqualToString:@"no"] ||
             [normalized isEqualToString:@"false"]);
}

#pragma mark - Drawing helpers

static NSColor *LHCColor(CGFloat r, CGFloat g, CGFloat b) {
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1.0];
}

static NSImage *LHCBackgroundImage(void) {
    static NSImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [NSImage imageWithSize:NSMakeSize(1600, 1000) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            NSGradient *base = [[NSGradient alloc] initWithColors:@[
                LHCColor(0.055, 0.105, 0.155),
                LHCColor(0.023, 0.047, 0.073),
                LHCColor(0.007, 0.013, 0.022)
            ]];
            [base drawInRect:rect angle:270];

            NSGradient *halo = [[NSGradient alloc] initWithColors:@[
                [NSColor colorWithSRGBRed:0.16 green:0.58 blue:0.90 alpha:0.22],
                [NSColor colorWithSRGBRed:0.05 green:0.20 blue:0.38 alpha:0.04],
                [NSColor clearColor]
            ]];
            [halo drawInRect:NSMakeRect(rect.size.width * 0.20, rect.size.height * 0.20,
                                        rect.size.width * 0.85, rect.size.height * 0.85)
      relativeCenterPosition:NSMakePoint(-0.15, 0.18)];

            NSGradient *violet = [[NSGradient alloc] initWithColors:@[
                [NSColor colorWithSRGBRed:0.48 green:0.18 blue:0.74 alpha:0.13],
                [NSColor clearColor]
            ]];
            [violet drawInRect:NSMakeRect(rect.size.width * 0.55, rect.size.height * 0.12,
                                          rect.size.width * 0.55, rect.size.height * 0.55)
        relativeCenterPosition:NSMakePoint(0.5, 0.5)];

            // Fine vignette lines give the backdrop a subtle studio depth.
            NSBezierPath *vignette = [NSBezierPath bezierPathWithRect:rect];
            [[NSColor colorWithCalibratedWhite:0.0 alpha:0.18] setStroke];
            vignette.lineWidth = 80;
            [vignette stroke];
            return YES;
        }];
    });
    return image;
}

static NSImage *LHCEnvironmentImage(void) {
    static NSImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [NSImage imageWithSize:NSMakeSize(1024, 512) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            NSGradient *sky = [[NSGradient alloc] initWithColors:@[
                LHCColor(0.22, 0.31, 0.42),
                LHCColor(0.06, 0.09, 0.13),
                LHCColor(0.01, 0.015, 0.025)
            ]];
            [sky drawInRect:rect angle:270];

            NSArray<NSValue *> *lights = @[
                [NSValue valueWithRect:NSMakeRect(190, 260, 260, 150)],
                [NSValue valueWithRect:NSMakeRect(650, 300, 180, 110)]
            ];
            for (NSValue *value in lights) {
                NSRect lightRect = value.rectValue;
                NSGradient *glow = [[NSGradient alloc] initWithColors:@[
                    [NSColor colorWithCalibratedWhite:1.0 alpha:0.9],
                    [NSColor colorWithCalibratedWhite:0.65 alpha:0.0]
                ]];
                [glow drawInRect:lightRect relativeCenterPosition:NSZeroPoint];
            }

            NSGradient *blueRim = [[NSGradient alloc] initWithColors:@[
                [NSColor colorWithSRGBRed:0.10 green:0.42 blue:0.80 alpha:0.55],
                [NSColor colorWithSRGBRed:0.02 green:0.04 blue:0.08 alpha:0.0]
            ]];
            [blueRim drawInRect:NSMakeRect(rect.size.width * 0.54, 0,
                                           rect.size.width * 0.6, rect.size.height * 0.6)
             relativeCenterPosition:NSMakePoint(0.85, 0.1)];
            return YES;
        }];
    });
    return image;
}

static NSImage *LHCTerrainTexture(void) {
    static NSImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [NSImage imageWithSize:NSMakeSize(1024, 1024) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            NSGradient *earth = [[NSGradient alloc] initWithColors:@[
                LHCColor(0.63, 0.59, 0.50),
                LHCColor(0.50, 0.45, 0.37),
                LHCColor(0.36, 0.32, 0.26)
            ]];
            [earth drawInRect:rect angle:45];

            // Fine aggregate / mineral speckle.
            for (NSInteger i = 0; i < 5200; i++) {
                CGFloat x = (CGFloat)arc4random_uniform(1024);
                CGFloat y = (CGFloat)arc4random_uniform(1024);
                CGFloat radius = 0.5 + (CGFloat)arc4random_uniform(100) / 100.0 * 2.4;
                CGFloat alpha = 0.025 + (CGFloat)arc4random_uniform(100) / 100.0 * 0.095;
                BOOL lighter = arc4random_uniform(2) == 0;
                NSColor *color = lighter
                    ? [NSColor colorWithCalibratedWhite:1.0 alpha:alpha]
                    : [NSColor colorWithCalibratedWhite:0.12 alpha:alpha];
                [color setFill];
                [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, y, radius, radius)] fill];
            }

            // Concrete service apron around the accelerator ring.
            NSBezierPath *apron = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 48, 48)];
            NSBezierPath *apronHole = [NSBezierPath bezierPathWithOvalInRect:
                NSMakeRect(512 - 315, 512 - 315, 630, 630)];
            [apron appendBezierPath:apronHole];
            apron.windingRule = NSWindingRuleEvenOdd;
            [[NSColor colorWithSRGBRed:0.28 green:0.30 blue:0.29 alpha:0.18] setFill];
            [apron fill];

            NSBezierPath *innerPad = [NSBezierPath bezierPathWithOvalInRect:
                NSMakeRect(512 - 302, 512 - 302, 604, 604)];
            [[NSColor colorWithSRGBRed:0.78 green:0.75 blue:0.66 alpha:0.10] setFill];
            [innerPad fill];

            // Faint survey contours.
            [NSGraphicsContext saveGraphicsState];
            NSBezierPath *clip = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 26, 26)];
            [clip addClip];
            for (NSInteger i = 0; i < 9; i++) {
                CGFloat inset = 68.0 + (CGFloat)i * 96.0;
                NSBezierPath *contour = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, inset, inset)];
                contour.lineWidth = 1.5;
                [[NSColor colorWithSRGBRed:0.21 green:0.22 blue:0.21 alpha:0.13] setStroke];
                [contour stroke];
            }

            // Service-road lane markers just outside the accelerator ring.
            [[NSColor colorWithSRGBRed:0.84 green:0.75 blue:0.48 alpha:0.30] setStroke];
            for (NSInteger i = 0; i < 48; i++) {
                CGFloat startAngle = (CGFloat)i / 48.0 * M_PI * 2.0;
                CGFloat endAngle = startAngle + (M_PI * 2.0 / 48.0) * 0.48;
                NSBezierPath *dash = [NSBezierPath bezierPath];
                [dash appendBezierPathWithArcWithCenter:NSMakePoint(512, 512)
                                                 radius:466
                                             startAngle:startAngle * 180.0 / M_PI
                                               endAngle:endAngle * 180.0 / M_PI];
                dash.lineWidth = 3.0;
                [dash stroke];
            }
            [NSGraphicsContext restoreGraphicsState];

            // Survey crosshairs.
            [[NSColor colorWithCalibratedWhite:0.14 alpha:0.10] setStroke];
            NSBezierPath *cross = [NSBezierPath bezierPath];
            [cross moveToPoint:NSMakePoint(512, 0)];
            [cross lineToPoint:NSMakePoint(512, 1024)];
            [cross moveToPoint:NSMakePoint(0, 512)];
            [cross lineToPoint:NSMakePoint(1024, 512)];
            cross.lineWidth = 2;
            [cross stroke];
            return YES;
        }];
    });
    return image;
}

static NSImage *LHCGrassTexture(void) {
    static NSImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [NSImage imageWithSize:NSMakeSize(1024, 1024) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            NSGradient *base = [[NSGradient alloc] initWithColors:@[
                LHCColor(0.20, 0.28, 0.17),
                LHCColor(0.13, 0.21, 0.12),
                LHCColor(0.24, 0.30, 0.18)
            ]];
            [base drawInRect:rect angle:35];

            // Broad, low-contrast patches keep the ground from reading as a
            // single flat green card while preserving the night-time palette.
            for (NSInteger i = 0; i < 72; i++) {
                CGFloat x = (CGFloat)arc4random_uniform(1024);
                CGFloat y = (CGFloat)arc4random_uniform(1024);
                CGFloat w = 34.0 + (CGFloat)arc4random_uniform(150);
                CGFloat h = 26.0 + (CGFloat)arc4random_uniform(110);
                NSColor *patch = (i % 3 == 0)
                    ? LHCColor(0.31, 0.27, 0.17)
                    : LHCColor(0.08, 0.16, 0.08);
                [[patch colorWithAlphaComponent:0.035 + (CGFloat)arc4random_uniform(70) / 1000.0] setFill];
                [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, y, w, h)] fill];
            }

            // Mowing bands add a little human-maintained scale to the site.
            for (NSInteger i = 0; i < 12; i++) {
                [[NSColor colorWithCalibratedWhite:1.0 alpha:0.007] setFill];
                NSRectFill(NSMakeRect(0, (CGFloat)i * 1024.0 / 12.0,
                                     1024, 1024.0 / 24.0));
            }

            // Grass blades and dry stalks.
            for (NSInteger i = 0; i < 9000; i++) {
                CGFloat x = (CGFloat)arc4random_uniform(1024);
                CGFloat y = (CGFloat)arc4random_uniform(1024);
                CGFloat length = 1.5 + (CGFloat)arc4random_uniform(100) / 100.0 * 2.8;
                CGFloat alpha = 0.035 + (CGFloat)arc4random_uniform(100) / 100.0 * 0.10;
                NSColor *color = (arc4random_uniform(4) == 0)
                    ? [NSColor colorWithSRGBRed:0.52 green:0.43 blue:0.23 alpha:alpha]
                    : [NSColor colorWithSRGBRed:0.30 green:0.48 blue:0.22 alpha:alpha];
                [color setFill];
                NSRectFill(NSMakeRect(x, y, 1.0, length));
            }

            // Sparse stones and exposed soil.
            for (NSInteger i = 0; i < 520; i++) {
                CGFloat x = (CGFloat)arc4random_uniform(1024);
                CGFloat y = (CGFloat)arc4random_uniform(1024);
                CGFloat radius = 0.6 + (CGFloat)arc4random_uniform(100) / 100.0 * 1.8;
                [[NSColor colorWithSRGBRed:0.45 green:0.42 blue:0.34
                                    alpha:0.05 + (CGFloat)arc4random_uniform(80) / 1000.0] setFill];
                [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, y, radius, radius)] fill];
            }
            return YES;
        }];
    });
    return image;
}

static NSImage *LHCAsphaltTexture(void) {
    static NSImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [NSImage imageWithSize:NSMakeSize(512, 512) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            NSGradient *base = [[NSGradient alloc] initWithColors:@[
                LHCColor(0.20, 0.21, 0.21),
                LHCColor(0.12, 0.13, 0.14),
                LHCColor(0.17, 0.18, 0.18)
            ]];
            [base drawInRect:rect angle:90];

            for (NSInteger i = 0; i < 4200; i++) {
                CGFloat x = (CGFloat)arc4random_uniform(512);
                CGFloat y = (CGFloat)arc4random_uniform(512);
                CGFloat radius = 0.4 + (CGFloat)arc4random_uniform(100) / 100.0 * 1.3;
                BOOL lighter = arc4random_uniform(2) == 0;
                NSColor *color = lighter
                    ? [NSColor colorWithCalibratedWhite:1.0 alpha:0.025 + (CGFloat)arc4random_uniform(50) / 1000.0]
                    : [NSColor colorWithCalibratedWhite:0.02 alpha:0.06 + (CGFloat)arc4random_uniform(60) / 1000.0];
                [color setFill];
                [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, y, radius, radius)] fill];
            }

            // Faint tire-worn bands along the direction of travel.
            for (NSInteger i = 0; i < 7; i++) {
                CGFloat y = 42.0 + (CGFloat)i * 68.0;
                [[NSColor colorWithCalibratedWhite:0.02 alpha:0.055] setFill];
                NSRectFill(NSMakeRect(0, y, 512, 9));
                [[NSColor colorWithCalibratedWhite:0.92 alpha:0.018] setFill];
                NSRectFill(NSMakeRect(0, y + 9, 512, 2));
            }
            return YES;
        }];
    });
    return image;
}

static CGFloat LHCSmoothStep(CGFloat edge0, CGFloat edge1, CGFloat x) {
    if (edge1 <= edge0) {
        return x >= edge1 ? 1.0 : 0.0;
    }
    CGFloat t = (x - edge0) / (edge1 - edge0);
    t = MIN(MAX(t, 0.0), 1.0);
    return t * t * (3.0 - 2.0 * t);
}

/// Height of the surrounding site relative to the plateau's lower soil layer.
/// The inner apron stays flat so the road and service buildings sit cleanly;
/// low-frequency undulation begins outside the accelerator fence.
static CGFloat LHCSiteHeight(CGFloat x, CGFloat z) {
    CGFloat radius = hypot(x, z);
    CGFloat slope = LHCSmoothStep(16.0, 31.0, radius);
    CGFloat undulation = 0.30 * sin(x * 0.17 + 0.4) * cos(z * 0.13 - 0.2)
                       + 0.18 * sin(x * 0.31 - 1.1) * sin(z * 0.27 + 0.7)
                       + 0.08 * cos(x * 0.53 + z * 0.41);
    CGFloat height = slope * (0.26 + undulation);
    CGFloat distant = LHCSmoothStep(36.0, 58.0, radius);
    height += distant * (0.85 + 0.28 * sin(x * 0.08 + z * 0.06)
                       + 0.18 * sin(x * 0.19 - z * 0.11));
    return MAX(-0.04, height);
}

static SCNVector3 LHCSiteNormal(CGFloat x, CGFloat z) {
    const CGFloat epsilon = 0.35;
    CGFloat dx = (LHCSiteHeight(x + epsilon, z) - LHCSiteHeight(x - epsilon, z)) / (2.0 * epsilon);
    CGFloat dz = (LHCSiteHeight(x, z + epsilon) - LHCSiteHeight(x, z - epsilon)) / (2.0 * epsilon);
    SCNVector3 normal = SCNVector3Make(-dx, 1.0, -dz);
    CGFloat length = sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
    if (length > 0.0001) {
        normal.x /= length;
        normal.y /= length;
        normal.z /= length;
    }
    return normal;
}

static SCNGeometry *LHCSiteGroundGeometry(SCNMaterial *material) {
    const NSInteger segments = 128;
    const CGFloat size = 120.0;
    const CGFloat step = size / (CGFloat)segments;
    const NSInteger vertexCount = (segments + 1) * (segments + 1);

    SCNVector3 *positions = malloc(sizeof(SCNVector3) * (size_t)vertexCount);
    SCNVector3 *normals = malloc(sizeof(SCNVector3) * (size_t)vertexCount);
    CGPoint *uvs = malloc(sizeof(CGPoint) * (size_t)vertexCount);
    uint32_t *indices = malloc(sizeof(uint32_t) * (size_t)segments * (size_t)segments * 6);

    for (NSInteger iz = 0; iz <= segments; iz++) {
        for (NSInteger ix = 0; ix <= segments; ix++) {
            NSInteger index = iz * (segments + 1) + ix;
            CGFloat x = -size * 0.5 + (CGFloat)ix * step;
            CGFloat z = -size * 0.5 + (CGFloat)iz * step;
            positions[index] = SCNVector3Make(x, LHCSiteHeight(x, z), z);
            normals[index] = LHCSiteNormal(x, z);
            uvs[index] = CGPointMake(x / 14.0, z / 14.0);
        }
    }

    NSInteger index = 0;
    for (NSInteger iz = 0; iz < segments; iz++) {
        for (NSInteger ix = 0; ix < segments; ix++) {
            uint32_t a = (uint32_t)(iz * (segments + 1) + ix);
            uint32_t b = a + 1;
            uint32_t c = a + (uint32_t)(segments + 1);
            uint32_t d = c + 1;
            indices[index++] = a;
            indices[index++] = c;
            indices[index++] = b;
            indices[index++] = b;
            indices[index++] = c;
            indices[index++] = d;
        }
    }

    SCNGeometrySource *vertexSource = [SCNGeometrySource geometrySourceWithVertices:positions
                                                                            count:vertexCount];
    SCNGeometrySource *normalSource = [SCNGeometrySource geometrySourceWithNormals:normals
                                                                            count:vertexCount];
    SCNGeometrySource *uvSource = [SCNGeometrySource geometrySourceWithTextureCoordinates:uvs
                                                                                    count:vertexCount];
    NSData *indexData = [NSData dataWithBytes:indices
                                       length:sizeof(uint32_t) * (NSUInteger)index];
    SCNGeometryElement *element = [SCNGeometryElement geometryElementWithData:indexData
                                                               primitiveType:SCNGeometryPrimitiveTypeTriangles
                                                              primitiveCount:(NSInteger)segments * (NSInteger)segments * 2
                                                               bytesPerIndex:sizeof(uint32_t)];
    SCNGeometry *geometry = [SCNGeometry geometryWithSources:@[vertexSource, normalSource, uvSource]
                                                     elements:@[element]];
    geometry.materials = @[material];

    free(positions);
    free(normals);
    free(uvs);
    free(indices);
    return geometry;
}

static SCNGeometry *LHCAnnulusGeometry(CGFloat innerRadius, CGFloat outerRadius,
                                       CGFloat height, SCNMaterial *material) {
    const NSInteger segments = 192;
    const NSInteger vertexCount = (segments + 1) * 2;
    SCNVector3 *positions = malloc(sizeof(SCNVector3) * (size_t)vertexCount);
    SCNVector3 *normals = malloc(sizeof(SCNVector3) * (size_t)vertexCount);
    CGPoint *uvs = malloc(sizeof(CGPoint) * (size_t)vertexCount);
    uint32_t *indices = malloc(sizeof(uint32_t) * (size_t)segments * 6);

    for (NSInteger i = 0; i <= segments; i++) {
        CGFloat angle = (CGFloat)i / (CGFloat)segments * M_PI * 2.0;
        CGFloat cosine = cos(angle);
        CGFloat sine = sin(angle);
        NSInteger base = i * 2;
        positions[base] = SCNVector3Make(cosine * innerRadius, height, sine * innerRadius);
        positions[base + 1] = SCNVector3Make(cosine * outerRadius, height, sine * outerRadius);
        normals[base] = SCNVector3Make(0, 1, 0);
        normals[base + 1] = SCNVector3Make(0, 1, 0);
        uvs[base] = CGPointMake((CGFloat)i / (CGFloat)segments * 14.0, 0);
        uvs[base + 1] = CGPointMake((CGFloat)i / (CGFloat)segments * 14.0, 1);
    }

    NSInteger index = 0;
    for (NSInteger i = 0; i < segments; i++) {
        uint32_t a = (uint32_t)(i * 2);
        uint32_t b = a + 1;
        uint32_t c = (uint32_t)((i + 1) * 2);
        uint32_t d = c + 1;
        indices[index++] = a;
        indices[index++] = c;
        indices[index++] = b;
        indices[index++] = b;
        indices[index++] = c;
        indices[index++] = d;
    }

    SCNGeometrySource *vertexSource = [SCNGeometrySource geometrySourceWithVertices:positions
                                                                            count:vertexCount];
    SCNGeometrySource *normalSource = [SCNGeometrySource geometrySourceWithNormals:normals
                                                                            count:vertexCount];
    SCNGeometrySource *uvSource = [SCNGeometrySource geometrySourceWithTextureCoordinates:uvs
                                                                                    count:vertexCount];
    NSData *indexData = [NSData dataWithBytes:indices
                                       length:sizeof(uint32_t) * (NSUInteger)index];
    SCNGeometryElement *element = [SCNGeometryElement geometryElementWithData:indexData
                                                               primitiveType:SCNGeometryPrimitiveTypeTriangles
                                                              primitiveCount:(NSInteger)segments * 2
                                                               bytesPerIndex:sizeof(uint32_t)];
    SCNGeometry *geometry = [SCNGeometry geometryWithSources:@[vertexSource, normalSource, uvSource]
                                                     elements:@[element]];
    geometry.materials = @[material];

    free(positions);
    free(normals);
    free(uvs);
    free(indices);
    return geometry;
}

static NSImage *LHCPanelTexture(NSColor *base, NSColor *accent, NSInteger divisions) {
    return [NSImage imageWithSize:NSMakeSize(512, 512) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSColor *top = [base blendedColorWithFraction:0.16 ofColor:[NSColor whiteColor]] ?: base;
        NSColor *bottom = [base blendedColorWithFraction:0.25 ofColor:[NSColor blackColor]] ?: base;
        NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:top endingColor:bottom];
        [gradient drawInRect:rect angle:90];

        CGFloat width = rect.size.width / (CGFloat)MAX(divisions, 1);
        for (NSInteger i = 0; i < divisions; i++) {
            CGFloat x = i * width;
            [[NSColor colorWithCalibratedWhite:0.02 alpha:0.24] setFill];
            NSRectFill(NSMakeRect(x, 0, 2, rect.size.height));
            [[NSColor colorWithCalibratedWhite:1.0 alpha:0.055] setFill];
            NSRectFill(NSMakeRect(x + 2, 0, 2, rect.size.height));
            [[NSColor colorWithCalibratedWhite:0.98 alpha:0.08] setFill];
            NSRectFill(NSMakeRect(x + width * 0.10, rect.size.height - 28, width * 0.42, 2));
        }

        for (NSInteger row = 1; row < 4; row++) {
            CGFloat y = rect.size.height * (CGFloat)row / 4.0;
            [[NSColor colorWithCalibratedWhite:0.02 alpha:0.23] setFill];
            NSRectFill(NSMakeRect(0, y, rect.size.width, 2));
            [[NSColor colorWithCalibratedWhite:1.0 alpha:0.04] setFill];
            NSRectFill(NSMakeRect(0, y + 2, rect.size.width, 1));
        }

        // Accent glints / bolts break up the repetition.
        [[accent colorWithAlphaComponent:0.16] setFill];
        for (NSInteger i = 0; i < divisions; i += 2) {
            CGFloat x = i * width;
            NSRectFill(NSMakeRect(x + width * 0.62, rect.size.height * 0.5, width * 0.18, rect.size.height * 0.46));
        }
        [[NSColor colorWithCalibratedWhite:0.86 alpha:0.42] setFill];
        for (NSInteger i = 0; i < divisions; i++) {
            CGFloat x = i * width + width * 0.5;
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 2.5, 14, 5, 5)] fill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 2.5, rect.size.height - 19, 5, 5)] fill];
        }
        return YES;
    }];
}

static NSImage *LHCBrushedNormalImage(void) {
    static NSImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const NSInteger side = 256;
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
                          pixelsWide:side
                          pixelsHigh:side
                       bitsPerSample:8
                     samplesPerPixel:4
                            hasAlpha:YES
                            isPlanar:NO
                      colorSpaceName:NSDeviceRGBColorSpace
                         bytesPerRow:side * 4
                        bitsPerPixel:32];
        unsigned char *pixels = rep.bitmapData;
        for (NSInteger y = 0; y < side; y++) {
            for (NSInteger x = 0; x < side; x++) {
                // Low-amplitude normal perturbation gives painted and brushed
                // metal surfaces a subtle micro-surface without obvious noise.
                CGFloat fine = ((CGFloat)arc4random_uniform(1000) / 1000.0 - 0.5);
                CGFloat streak = sin((CGFloat)y * 0.73 + (CGFloat)x * 0.035) * 0.018;
                CGFloat nx = (fine * 0.16 + streak) * 0.55;
                CGFloat ny = (fine * 0.10 - streak) * 0.55;
                CGFloat nz = sqrt(MAX(0.001, 1.0 - nx * nx - ny * ny));
                NSInteger offset = (y * side + x) * 4;
                pixels[offset + 0] = (unsigned char)lrint((nx * 0.5 + 0.5) * 255.0);
                pixels[offset + 1] = (unsigned char)lrint((ny * 0.5 + 0.5) * 255.0);
                pixels[offset + 2] = (unsigned char)lrint((nz * 0.5 + 0.5) * 255.0);
                pixels[offset + 3] = 255;
            }
        }
        image = [[NSImage alloc] initWithSize:NSMakeSize(side, side)];
        [image addRepresentation:rep];
    });
    return image;
}

static NSImage *LHCLabelImage(NSString *text, NSColor *accent) {
    NSFont *font = [NSFont systemFontOfSize:42 weight:NSFontWeightSemibold];
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor colorWithSRGBRed:0.97 green:0.98 blue:1.0 alpha:1.0]
    };
    NSSize textSize = [text sizeWithAttributes:attributes];
    NSSize size = NSMakeSize(ceil(textSize.width) + 82, 76);
    return [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSRect backgroundRect = NSInsetRect(rect, 2, 2);
        NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:backgroundRect
                                                                  xRadius:16
                                                                  yRadius:16];
        [[NSColor colorWithSRGBRed:0.025 green:0.045 blue:0.07 alpha:0.76] setFill];
        [background fill];
        [accent setStroke];
        background.lineWidth = 2.2;
        [background stroke];

        [accent setFill];
        NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(22, (size.height - 13.0) / 2.0, 13, 13)];
        [dot fill];

        [text drawAtPoint:NSMakePoint(49, (size.height - textSize.height) / 2.0)
           withAttributes:attributes];
        return YES;
    }];
}

static SCNMaterial *LHCPBRMaterial(NSColor *color, CGFloat roughness, CGFloat metalness) {
    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelPhysicallyBased;
    material.diffuse.contents = color;
    material.roughness.contents = @(roughness);
    material.metalness.contents = @(metalness);
    material.normal.contents = LHCBrushedNormalImage();
    material.normal.intensity = 0.16;
    material.normal.wrapS = SCNWrapModeRepeat;
    material.normal.wrapT = SCNWrapModeRepeat;
    material.normal.maxAnisotropy = 8.0;
    material.clearCoat.contents = @(metalness > 0.72 ? 0.16 : 0.05);
    material.clearCoatRoughness.contents = @0.34;
    material.fresnelExponent = 1.4;
    return material;
}

static SCNMaterial *LHCEmissiveMaterial(NSColor *color, CGFloat intensity) {
    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelConstant;
    material.diffuse.contents = [color colorWithAlphaComponent:0.18];
    material.emission.contents = color;
    material.emission.intensity = intensity;
    material.writesToDepthBuffer = NO;
    return material;
}

static SCNMaterial *LHCPanelMaterial(NSColor *base, NSColor *accent, CGFloat roughness, CGFloat metalness) {
    SCNMaterial *material = LHCPBRMaterial(base, roughness, metalness);
    material.diffuse.contents = LHCPanelTexture(base, accent, 8);
    return material;
}

static SCNNode *LHCGeometryNode(SCNGeometry *geometry, SCNMaterial *material, SCNVector3 position) {
    geometry.materials = @[material];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    node.position = position;
    return node;
}

static SCNNode *LHCBox(SCNVector3 size, CGFloat chamfer, SCNMaterial *material, SCNVector3 position) {
    SCNBox *box = [SCNBox boxWithWidth:size.x height:size.y length:size.z chamferRadius:chamfer];
    box.chamferSegmentCount = 6;
    box.widthSegmentCount = 2;
    box.heightSegmentCount = 2;
    box.lengthSegmentCount = 2;
    return LHCGeometryNode(box, material, position);
}

static SCNNode *LHCCylinder(CGFloat radius, CGFloat length, SCNMaterial *material,
                             SCNVector3 position, BOOL alongX) {
    SCNCylinder *cylinder = [SCNCylinder cylinderWithRadius:radius height:length];
    cylinder.radialSegmentCount = radius > 0.7 ? 128 : (radius > 0.2 ? 72 : 40);
    cylinder.heightSegmentCount = 4;
    SCNNode *node = LHCGeometryNode(cylinder, material, position);
    if (alongX) {
        node.eulerAngles = SCNVector3Make(0, 0, M_PI_2);
    }
    return node;
}

static SCNNode *LHCTorus(CGFloat ringRadius, CGFloat pipeRadius, SCNMaterial *material,
                         SCNVector3 position, BOOL aroundX) {
    SCNTorus *torus = [SCNTorus torusWithRingRadius:ringRadius pipeRadius:pipeRadius];
    torus.ringSegmentCount = ringRadius > 2.0 ? 180 : 128;
    torus.pipeSegmentCount = pipeRadius > 0.06 ? 32 : 20;
    SCNNode *node = LHCGeometryNode(torus, material, position);
    if (aroundX) {
        node.eulerAngles = SCNVector3Make(0, 0, M_PI_2);
    }
    return node;
}

static SCNNode *LHCCone(CGFloat topRadius, CGFloat bottomRadius, CGFloat height,
                         SCNMaterial *material, SCNVector3 position, BOOL alongX) {
    SCNCone *cone = [SCNCone coneWithTopRadius:topRadius bottomRadius:bottomRadius height:height];
    cone.radialSegmentCount = 96;
    cone.heightSegmentCount = 6;
    SCNNode *node = LHCGeometryNode(cone, material, position);
    if (alongX) {
        node.eulerAngles = SCNVector3Make(0, 0, -M_PI_2);
    }
    return node;
}

/// A rounded, hollow race-track shape extruded along Z. This is used for the
/// ATLAS barrel coils, which read as flat boxes when built from SCNBox.
static SCNNode *LHCRoundedLoop(CGFloat width, CGFloat height, CGFloat cornerRadius,
                                CGFloat wallThickness, CGFloat depth,
                                SCNMaterial *material, SCNVector3 position) {
    NSRect outerRect = NSMakeRect(-width * 0.5, -height * 0.5, width, height);
    NSRect innerRect = NSInsetRect(outerRect, wallThickness, wallThickness);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:outerRect
                                                         xRadius:cornerRadius
                                                         yRadius:cornerRadius];
    NSBezierPath *hole = [NSBezierPath bezierPathWithRoundedRect:innerRect
                                                         xRadius:MAX(0.02, cornerRadius - wallThickness)
                                                         yRadius:MAX(0.02, cornerRadius - wallThickness)];
    [path appendBezierPath:hole];
    path.windingRule = NSWindingRuleEvenOdd;

    SCNShape *shape = [SCNShape shapeWithPath:path extrusionDepth:depth];
    shape.chamferMode = SCNChamferModeBoth;
    shape.chamferRadius = MIN(0.035, depth * 0.35);
    shape.chamferProfile = nil;
    shape.materials = @[material];

    SCNNode *node = [SCNNode nodeWithGeometry:shape];
    node.position = SCNVector3Make(position.x, position.y, position.z - depth * 0.5);
    return node;
}

/// A flat annular sector used for calorimeter wheels and muon endcaps.
static SCNNode *LHCRingSector(CGFloat innerRadius, CGFloat outerRadius,
                               CGFloat startDegrees, CGFloat endDegrees,
                               CGFloat depth, SCNMaterial *material,
                               SCNVector3 position) {
    const NSInteger steps = 18;
    CGFloat start = startDegrees * M_PI / 180.0;
    CGFloat end = endDegrees * M_PI / 180.0;
    NSBezierPath *path = [NSBezierPath bezierPath];
    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat angle = start + (end - start) * (CGFloat)i / (CGFloat)steps;
        NSPoint p = NSMakePoint(cos(angle) * outerRadius, sin(angle) * outerRadius);
        if (i == 0) {
            [path moveToPoint:p];
        } else {
            [path lineToPoint:p];
        }
    }
    [path lineToPoint:NSMakePoint(cos(end) * innerRadius, sin(end) * innerRadius)];
    for (NSInteger i = steps; i >= 0; i--) {
        CGFloat angle = start + (end - start) * (CGFloat)i / (CGFloat)steps;
        [path lineToPoint:NSMakePoint(cos(angle) * innerRadius, sin(angle) * innerRadius)];
    }
    [path closePath];

    SCNShape *shape = [SCNShape shapeWithPath:path extrusionDepth:depth];
    shape.chamferMode = SCNChamferModeBoth;
    shape.chamferRadius = MIN(0.02, depth * 0.35);
    shape.materials = @[material];
    SCNNode *node = [SCNNode nodeWithGeometry:shape];
    node.position = SCNVector3Make(position.x, position.y, position.z - depth * 0.5);
    return node;
}

#pragma mark - Site infrastructure

static void LHCAddServiceRoad(SCNNode *terrain) {
    SCNMaterial *asphalt = [SCNMaterial material];
    asphalt.lightingModelName = SCNLightingModelPhysicallyBased;
    asphalt.diffuse.contents = LHCAsphaltTexture();
    asphalt.roughness.contents = @0.93;
    asphalt.metalness.contents = @0.03;
    asphalt.normal.contents = LHCBrushedNormalImage();
    asphalt.normal.intensity = 0.12;
    asphalt.normal.wrapS = SCNWrapModeRepeat;
    asphalt.normal.wrapT = SCNWrapModeRepeat;
    asphalt.normal.maxAnisotropy = 8.0;
    asphalt.doubleSided = YES;

    SCNGeometry *roadGeometry = LHCAnnulusGeometry(LHCSiteRoadInnerRadius,
                                                   LHCSiteRoadOuterRadius,
                                                   0.012,
                                                   asphalt);
    SCNNode *road = [SCNNode nodeWithGeometry:roadGeometry];
    road.position = SCNVector3Make(0, LHCSiteBaseY, 0);
    road.name = @"part.terrain.road";
    road.castsShadow = NO;
    [terrain addChildNode:road];

    SCNMaterial *curb = LHCPBRMaterial(LHCColor(0.43, 0.42, 0.37), 0.88, 0.0);
    for (NSNumber *radius in @[@(LHCSiteRoadInnerRadius - 0.05),
                                @(LHCSiteRoadOuterRadius + 0.05)]) {
        SCNNode *edge = LHCTorus(radius.doubleValue, 0.028, curb,
                                 SCNVector3Make(0, LHCSiteBaseY + 0.018, 0), NO);
        edge.castsShadow = NO;
        [terrain addChildNode:edge];
    }

    SCNMaterial *marking = LHCPBRMaterial(LHCColor(0.76, 0.70, 0.52), 0.72, 0.0);
    marking.emission.contents = LHCColor(0.90, 0.75, 0.40);
    marking.emission.intensity = 0.16;
    const CGFloat laneRadius = (LHCSiteRoadInnerRadius + LHCSiteRoadOuterRadius) * 0.5;
    for (NSInteger i = 0; i < 72; i++) {
        CGFloat angle = (CGFloat)i / 72.0 * M_PI * 2.0;
        SCNNode *dash = LHCBox(SCNVector3Make(0.055, 0.012, 0.34), 0.002, marking,
                               SCNVector3Make(cos(angle) * laneRadius,
                                              LHCSiteBaseY + 0.026,
                                              sin(angle) * laneRadius));
        dash.eulerAngles = SCNVector3Make(0, -angle, 0);
        dash.castsShadow = NO;
        [terrain addChildNode:dash];
    }
}

static void LHCAddServiceBuilding(SCNNode *terrain, CGFloat angle) {
    const CGFloat radius = 17.7;
    CGFloat x = cos(angle) * radius;
    CGFloat z = sin(angle) * radius;

    SCNNode *root = [SCNNode node];
    root.name = @"part.terrain.building";
    root.position = SCNVector3Make(x, LHCSiteBaseY + LHCSiteHeight(x, z), z);
    // Local +Z points toward the accelerator ring, so the entrance and path
    // face the service road rather than the empty outside of the site.
    root.eulerAngles = SCNVector3Make(0, -angle - M_PI_2, 0);
    [terrain addChildNode:root];

    SCNMaterial *concrete = LHCPanelMaterial(LHCColor(0.44, 0.43, 0.39),
                                              LHCColor(0.16, 0.18, 0.19), 0.91, 0.0);
    SCNMaterial *roof = [SCNMaterial material];
    // A dark, unlit roof reads as tar/bitumen and avoids the blue rim light
    // turning every horizontal service roof into a glowing cyan panel.
    roof.lightingModelName = SCNLightingModelConstant;
    roof.diffuse.contents = LHCColor(0.0, 0.0, 0.0);
    SCNMaterial *darkMetal = LHCPBRMaterial(LHCColor(0.09, 0.11, 0.13), 0.44, 0.62);
    SCNMaterial *window = LHCEmissiveMaterial(LHCColor(1.0, 0.72, 0.35), 1.15);
    SCNMaterial *warning = LHCPBRMaterial(LHCColor(0.78, 0.58, 0.12), 0.68, 0.0);
    SCNMaterial *pathMaterial = LHCPBRMaterial(LHCColor(0.18, 0.19, 0.19), 0.94, 0.02);

    [root addChildNode:LHCBox(SCNVector3Make(2.55, 0.10, 1.65), 0.025, concrete,
                              SCNVector3Make(0, 0.05, 0))];
    [root addChildNode:LHCBox(SCNVector3Make(1.95, 0.62, 1.18), 0.030, concrete,
                              SCNVector3Make(0, 0.40, 0))];
    [root addChildNode:LHCBox(SCNVector3Make(2.12, 0.07, 1.34), 0.020, roof,
                              SCNVector3Make(0, 0.735, 0))];
    [root addChildNode:LHCBox(SCNVector3Make(2.16, 0.025, 1.38), 0.010, darkMetal,
                              SCNVector3Make(0, 0.775, 0))];

    // Recessed entrance and a warm wall lamp.
    [root addChildNode:LHCBox(SCNVector3Make(0.34, 0.42, 0.025), 0.006, darkMetal,
                              SCNVector3Make(0, 0.29, 0.596))];
    [root addChildNode:LHCBox(SCNVector3Make(0.40, 0.46, 0.018), 0.005, roof,
                              SCNVector3Make(0, 0.30, 0.584))];
    [root addChildNode:LHCBox(SCNVector3Make(0.15, 0.035, 0.03), 0.004, window,
                              SCNVector3Make(0, 0.56, 0.598))];

    for (NSNumber *offset in @[@(-0.62), @(0.62)]) {
        [root addChildNode:LHCBox(SCNVector3Make(0.38, 0.15, 0.020), 0.004, window,
                                  SCNVector3Make(offset.doubleValue, 0.47, 0.596))];
        [root addChildNode:LHCBox(SCNVector3Make(0.32, 0.15, 0.020), 0.004, window,
                                  SCNVector3Make(offset.doubleValue, 0.47, -0.596))];
        [root addChildNode:LHCBox(SCNVector3Make(0.020, 0.15, 0.34), 0.004, window,
                                  SCNVector3Make(0.986, 0.47, offset.doubleValue * 0.5))];
        [root addChildNode:LHCBox(SCNVector3Make(0.020, 0.15, 0.34), 0.004, window,
                                  SCNVector3Make(-0.986, 0.47, offset.doubleValue * 0.5))];
    }

    // A rear service door and lamp keep the building from becoming a dark
    // silhouette when the camera orbits behind it.
    [root addChildNode:LHCBox(SCNVector3Make(0.34, 0.42, 0.025), 0.006, darkMetal,
                              SCNVector3Make(0, 0.29, -0.596))];
    [root addChildNode:LHCBox(SCNVector3Make(0.15, 0.035, 0.03), 0.004, window,
                              SCNVector3Make(0, 0.56, -0.598))];

    // Rooftop plant gives the buildings a believable industrial silhouette.
    [root addChildNode:LHCCylinder(0.10, 0.14, darkMetal,
                                   SCNVector3Make(-0.55, 0.80, -0.15), NO)];
    [root addChildNode:LHCCylinder(0.075, 0.22, darkMetal,
                                   SCNVector3Make(0.47, 0.84, 0.18), NO)];
    [root addChildNode:LHCBox(SCNVector3Make(0.42, 0.16, 0.32), 0.012, roof,
                              SCNVector3Make(0.05, 0.82, -0.25))];
    [root addChildNode:LHCCylinder(0.035, 0.52, darkMetal,
                                   SCNVector3Make(0.72, 1.01, -0.36), NO)];
    [root addChildNode:LHCCylinder(0.012, 0.58, darkMetal,
                                   SCNVector3Make(-0.78, 1.11, -0.42), NO)];

    // Paved approach connects each building to the ring road.
    [root addChildNode:LHCBox(SCNVector3Make(0.85, 0.025, 2.80), 0.010, pathMaterial,
                              SCNVector3Make(0, 0.03, 1.85))];
    [root addChildNode:LHCBox(SCNVector3Make(1.95, 0.025, 0.06), 0.002, warning,
                              SCNVector3Make(0, 0.105, 0.605))];
    for (NSNumber *offset in @[@(-0.55), @(0.55)]) {
        [root addChildNode:LHCCylinder(0.028, 0.18, darkMetal,
                                       SCNVector3Make(offset.doubleValue, 0.11, 1.02), NO)];
    }
}

static void LHCAddSiteTrees(SCNNode *terrain) {
    SCNMaterial *trunk = LHCPBRMaterial(LHCColor(0.22, 0.15, 0.09), 0.96, 0.0);
    NSArray<SCNMaterial *> *canopies = @[
        LHCPBRMaterial(LHCColor(0.12, 0.26, 0.13), 0.94, 0.0),
        LHCPBRMaterial(LHCColor(0.16, 0.30, 0.15), 0.92, 0.0),
        LHCPBRMaterial(LHCColor(0.20, 0.34, 0.17), 0.95, 0.0)
    ];

    for (NSInteger i = 0; i < 64; i++) {
        CGFloat angle = (CGFloat)i * 2.3999632297 + 0.35;
        CGFloat radius = 19.5 + (CGFloat)((i * 17) % 23);

        BOOL nearBuilding = NO;
        for (NSInteger building = 0; building < 4; building++) {
            CGFloat buildingAngle = (CGFloat)building * M_PI_2;
            CGFloat delta = fabs(atan2(sin(angle - buildingAngle), cos(angle - buildingAngle)));
            if (radius < 23.5 && delta < 0.32) {
                nearBuilding = YES;
                break;
            }
        }
        if (nearBuilding) {
            continue;
        }

        CGFloat x = cos(angle) * radius;
        CGFloat z = sin(angle) * radius;
        CGFloat scale = 0.78 + (CGFloat)((i * 11) % 9) / 9.0 * 0.70;
        SCNNode *tree = [SCNNode node];
        tree.name = @"part.terrain.tree";
        tree.position = SCNVector3Make(x, LHCSiteBaseY + LHCSiteHeight(x, z), z);
        tree.castsShadow = YES;

        [tree addChildNode:LHCCylinder(0.035 * scale, 0.50 * scale, trunk,
                                       SCNVector3Make(0, 0.25 * scale, 0), NO)];

        SCNMaterial *canopyMaterial = canopies[(NSUInteger)(i % 3)];
        SCNSphere *crown = [SCNSphere sphereWithRadius:0.23 * scale];
        crown.segmentCount = 16;
        SCNNode *crownNode = LHCGeometryNode(crown, canopyMaterial,
                                             SCNVector3Make(0, 0.59 * scale, 0));
        crownNode.scale = SCNVector3Make(1.0, 0.86, 1.0);
        [tree addChildNode:crownNode];

        SCNSphere *upperCrown = [SCNSphere sphereWithRadius:0.16 * scale];
        upperCrown.segmentCount = 14;
        SCNNode *upperNode = LHCGeometryNode(upperCrown, canopyMaterial,
                                             SCNVector3Make(0.07 * scale, 0.73 * scale,
                                                            0.04 * scale));
        [tree addChildNode:upperNode];

        [terrain addChildNode:tree];
    }
}

#pragma mark - Model

@interface LHCHadronModel ()

@property (nonatomic, strong, readwrite) SCNScene *scene;
@property (nonatomic, strong, readwrite) SCNNode *cameraNode;
@property (nonatomic, strong, readwrite) SCNNode *terrainNode;
@property (nonatomic, strong, readwrite) SCNNode *tunnelNode;
@property (nonatomic, strong, readwrite) SCNNode *magnetsNode;
@property (nonatomic, strong, readwrite) SCNNode *detectorsNode;
@property (nonatomic, strong, readwrite) SCNNode *beamGroupA;
@property (nonatomic, strong, readwrite) SCNNode *beamGroupB;
@property (nonatomic, strong, readwrite) SCNNode *selectionNode;
@property (nonatomic, strong, readwrite) NSDictionary<NSString *, LHCPartInfo *> *partCatalog;
@property (nonatomic, strong, readwrite) NSArray<NSString *> *detectorIdentifiers;
@property (nonatomic, strong, readwrite) LHCSimulationConfig *configuration;
@property (nonatomic, strong) NSMutableDictionary<NSString *, LHCPartInfo *> *mutableCatalog;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCNNode *> *detectorNodes;
@property (nonatomic, strong) NSMutableArray<SCNNode *> *outerShells;
@property (nonatomic, strong) NSMutableArray<SCNNode *> *labelNodes;
@property (nonatomic, strong) SCNNode *labelsRoot;
@property (nonatomic, strong) SCNMaterial *tunnelMaterial;
@property (nonatomic, strong) SCNMaterial *selectionRingMaterial;
@property (nonatomic, weak) SCNNode *selectionRingNode;
@property (nonatomic, strong) NSArray<SCNNode *> *beamTracerRootsA;
@property (nonatomic, strong) NSArray<SCNNode *> *beamTracerRootsB;
@property (nonatomic) CGFloat beamPhase;
@property (nonatomic) BOOL built;

@end

@implementation LHCHadronModel

- (instancetype)initWithConfiguration:(LHCSimulationConfig *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _scene = [SCNScene scene];
        _mutableCatalog = [NSMutableDictionary dictionary];
        _detectorNodes = [NSMutableDictionary dictionary];
        _outerShells = [NSMutableArray array];
        _labelNodes = [NSMutableArray array];
        _detectorIdentifiers = @[@"atlas", @"cms", @"alice", @"lhcb"];
        _beamPhase = 0.0;
        _initialCameraPosition = SCNVector3Make(20.4, 19.6, 26.6);
        _cameraTarget = SCNVector3Make(0.0, 1.25, 0.0);
        _initialFieldOfView = 39.0;
    }
    return self;
}

- (void)buildScene {
    if (self.built) {
        return;
    }
    self.built = YES;

    [self buildPartCatalog];
    [self configureEnvironment];
    [self buildCameraAndLights];
    [self buildTerrain];
    [self buildTunnel];
    [self buildBeamGuides];
    [self buildMagnets];
    self.labelsRoot = [SCNNode node];
    self.labelsRoot.name = @"detector.labels";
    [self.scene.rootNode addChildNode:self.labelsRoot];
    [self buildDetectors];
    [self buildProtonBunches];
    [self buildSelectionIndicator];
    [self applyModelConfiguration:self.configuration];
}

#pragma mark Scene environment

- (void)configureEnvironment {
    self.scene.background.contents = LHCBackgroundImage();
    self.scene.lightingEnvironment.contents = LHCEnvironmentImage();
    self.scene.lightingEnvironment.intensity = 1.28;
    self.scene.fogColor = LHCColor(0.012, 0.027, 0.043);
    self.scene.fogStartDistance = 58.0;
    self.scene.fogEndDistance = 115.0;
    self.scene.fogDensityExponent = 1.75;
}

- (void)buildCameraAndLights {
    SCNCamera *camera = [SCNCamera camera];
    camera.fieldOfView = self.initialFieldOfView;
    camera.zNear = 0.1;
    camera.zFar = 180.0;
    // SceneKit's HDR post-processing creates a texture view of a memoryless
    // render target, which Metal API validation flags as invalid. The debug
    // scheme disables validation for the normal Xcode experience, but keep an
    // LDR fallback for validation-enabled runs so the debugger cannot be
    // interrupted by SceneKit's internal render target setup.
    camera.wantsHDR = !LHCEnvironmentFlagIsEnabled(@"MTL_DEBUG_LAYER");
    camera.wantsExposureAdaptation = NO;
    camera.exposureOffset = 0.28;
    camera.bloomIntensity = 0.78;
    camera.bloomThreshold = 0.86;
    camera.bloomBlurRadius = 11.0;
    camera.bloomIterationCount = 4;
    camera.bloomIterationSpread = 0.82;
    camera.screenSpaceAmbientOcclusionIntensity = 1.45;
    camera.screenSpaceAmbientOcclusionRadius = 3.8;
    camera.screenSpaceAmbientOcclusionBias = 0.012;
    camera.vignettingIntensity = 0.76;
    camera.vignettingPower = 2.0;
    camera.saturation = 1.08;
    camera.contrast = 1.06;

    self.cameraNode = [SCNNode node];
    self.cameraNode.name = @"camera";
    self.cameraNode.camera = camera;
    self.cameraNode.position = self.initialCameraPosition;
    [self.cameraNode lookAt:self.cameraTarget
                        up:SCNVector3Make(0, 1, 0)
                localFront:SCNVector3Make(0, 0, -1)];
    [self.scene.rootNode addChildNode:self.cameraNode];

    SCNLight *ambient = [SCNLight light];
    ambient.type = SCNLightTypeAmbient;
    ambient.color = LHCColor(0.30, 0.42, 0.58);
    ambient.intensity = 215.0;
    SCNNode *ambientNode = [SCNNode node];
    ambientNode.light = ambient;
    [self.scene.rootNode addChildNode:ambientNode];

    SCNLight *key = [SCNLight light];
    key.type = SCNLightTypeDirectional;
    key.color = LHCColor(1.0, 0.94, 0.86);
    key.intensity = 1560.0;
    key.castsShadow = YES;
    key.shadowMapSize = CGSizeMake(4096, 4096);
    key.shadowSampleCount = 22;
    key.shadowRadius = 4.6;
    key.shadowBias = 0.0012;
    key.shadowColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.72];
    key.orthographicScale = 34.0;
    key.zNear = 1.0;
    key.zFar = 70.0;
    key.automaticallyAdjustsShadowProjection = YES;
    SCNNode *keyNode = [SCNNode node];
    keyNode.light = key;
    keyNode.position = SCNVector3Make(13, 22, 15);
    [keyNode lookAt:SCNVector3Make(0, 0.6, 0) up:SCNVector3Make(0, 1, 0) localFront:SCNVector3Make(0, 0, -1)];
    [self.scene.rootNode addChildNode:keyNode];

    SCNLight *fill = [SCNLight light];
    fill.type = SCNLightTypeDirectional;
    fill.color = LHCColor(0.54, 0.74, 1.0);
    fill.intensity = 620.0;
    SCNNode *fillNode = [SCNNode node];
    fillNode.light = fill;
    fillNode.position = SCNVector3Make(-18, 12, 13);
    [fillNode lookAt:SCNVector3Make(0, 1.0, 0) up:SCNVector3Make(0, 1, 0) localFront:SCNVector3Make(0, 0, -1)];
    [self.scene.rootNode addChildNode:fillNode];

    SCNLight *rim = [SCNLight light];
    rim.type = SCNLightTypeDirectional;
    rim.color = LHCColor(0.24, 0.80, 1.0);
    rim.intensity = 1180.0;
    SCNNode *rimNode = [SCNNode node];
    rimNode.light = rim;
    rimNode.position = SCNVector3Make(-8, 14, -18);
    [rimNode lookAt:SCNVector3Make(0, 1.0, 0) up:SCNVector3Make(0, 1, 0) localFront:SCNVector3Make(0, 0, -1)];
    [self.scene.rootNode addChildNode:rimNode];

    // A wide, soft warm bounce keeps the deep under-structure from turning
    // into a silhouette while the directional key defines the hard edges.
    SCNLight *bounce = [SCNLight light];
    bounce.type = SCNLightTypeOmni;
    bounce.color = LHCColor(1.0, 0.76, 0.56);
    bounce.intensity = 260.0;
    bounce.attenuationStartDistance = 3.0;
    bounce.attenuationEndDistance = 22.0;
    SCNNode *bounceNode = [SCNNode node];
    bounceNode.light = bounce;
    bounceNode.position = SCNVector3Make(1.5, 9.5, 4.0);
    [self.scene.rootNode addChildNode:bounceNode];
}

#pragma mark Terrain

- (void)buildTerrain {
    SCNNode *terrain = [SCNNode node];
    terrain.name = @"part.overview";
    [self.scene.rootNode addChildNode:terrain];
    self.terrainNode = terrain;

    SCNMaterial *groundMaterial = [SCNMaterial material];
    groundMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    groundMaterial.diffuse.contents = LHCTerrainTexture();
    groundMaterial.roughness.contents = @0.86;
    groundMaterial.metalness.contents = @0.03;
    groundMaterial.normal.contents = LHCBrushedNormalImage();
    groundMaterial.normal.intensity = 0.24;
    groundMaterial.normal.wrapS = SCNWrapModeRepeat;
    groundMaterial.normal.wrapT = SCNWrapModeRepeat;
    groundMaterial.normal.maxAnisotropy = 8.0;

    SCNMaterial *earthMaterial = LHCPanelMaterial(LHCColor(0.34, 0.28, 0.21),
                                                  LHCColor(0.10, 0.08, 0.06), 0.98, 0.0);
    SCNMaterial *earthLightMaterial = LHCPBRMaterial(LHCColor(0.46, 0.38, 0.29), 0.95, 0.0);
    SCNMaterial *earthDarkMaterial = LHCPBRMaterial(LHCColor(0.26, 0.20, 0.15), 0.98, 0.0);

    // Thin, elliptical survey plateau.  Layers create a readable soil section.
    SCNNode *top = LHCCylinder(13.0, 0.10, groundMaterial, SCNVector3Make(0, -0.05, 0), NO);
    ((SCNCylinder *)top.geometry).radialSegmentCount = 180;
    [terrain addChildNode:top];

    SCNNode *soil1 = LHCCylinder(12.96, 0.42, earthMaterial, SCNVector3Make(0, -0.30, 0), NO);
    ((SCNCylinder *)soil1.geometry).radialSegmentCount = 180;
    [terrain addChildNode:soil1];

    SCNNode *soil2 = LHCCylinder(13.18, 0.30, earthLightMaterial, SCNVector3Make(0, -0.65, 0), NO);
    ((SCNCylinder *)soil2.geometry).radialSegmentCount = 180;
    [terrain addChildNode:soil2];

    SCNNode *soil3 = LHCCylinder(13.42, 0.28, earthDarkMaterial, SCNVector3Make(0, -0.94, 0), NO);
    ((SCNCylinder *)soil3.geometry).radialSegmentCount = 180;
    [terrain addChildNode:soil3];

    SCNNode *soil4 = LHCCylinder(13.62, 0.22, earthMaterial, SCNVector3Make(0, -1.19, 0), NO);
    ((SCNCylinder *)soil4.geometry).radialSegmentCount = 180;
    [terrain addChildNode:soil4];

    terrain.scale = SCNVector3Make(1.16, 1.0, 0.93);

    // The accelerator sits on a raised survey plateau; the surrounding site
    // grounds it with rolling terrain, a service road, plant buildings and a
    // sparse tree line. Everything is procedural and shares the terrain node's
    // visibility toggle.
    SCNMaterial *grassMaterial = [SCNMaterial material];
    grassMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    grassMaterial.diffuse.contents = LHCGrassTexture();
    grassMaterial.diffuse.wrapS = SCNWrapModeRepeat;
    grassMaterial.diffuse.wrapT = SCNWrapModeRepeat;
    grassMaterial.roughness.contents = @0.96;
    grassMaterial.metalness.contents = @0.0;
    grassMaterial.normal.contents = LHCBrushedNormalImage();
    grassMaterial.normal.intensity = 0.10;
    grassMaterial.normal.wrapS = SCNWrapModeRepeat;
    grassMaterial.normal.wrapT = SCNWrapModeRepeat;
    grassMaterial.normal.maxAnisotropy = 8.0;

    SCNNode *siteGround = [SCNNode nodeWithGeometry:LHCSiteGroundGeometry(grassMaterial)];
    siteGround.name = @"part.terrain.site";
    siteGround.position = SCNVector3Make(0, LHCSiteBaseY, 0);
    siteGround.castsShadow = NO;
    [terrain addChildNode:siteGround];

    LHCAddServiceRoad(terrain);
    for (NSInteger i = 0; i < 4; i++) {
        LHCAddServiceBuilding(terrain, (CGFloat)i * M_PI_2);
    }
    LHCAddSiteTrees(terrain);

    // Faint illuminated survey rings laid into the plateau.
    SCNMaterial *surveyMaterial = LHCEmissiveMaterial(LHCColor(0.30, 0.78, 1.0), 0.45);
    surveyMaterial.transparency = 0.16;
    for (NSNumber *radius in @[@8.25, @10.9, @12.45]) {
        SCNNode *ring = LHCTorus(radius.doubleValue, 0.012, surveyMaterial,
                                 SCNVector3Make(0, 0.012, 0), NO);
        ring.castsShadow = NO;
        [terrain addChildNode:ring];
    }

    // Small radial tick marks around the outermost survey ring.
    SCNMaterial *tickMaterial = LHCEmissiveMaterial(LHCColor(0.32, 0.70, 0.92), 0.35);
    tickMaterial.transparency = 0.13;
    for (NSInteger i = 0; i < 24; i++) {
        CGFloat angle = (CGFloat)i / 24.0 * M_PI * 2.0;
        SCNNode *tick = LHCBox(SCNVector3Make(0.20, 0.012, 0.024), 0.002, tickMaterial,
                               SCNVector3Make(cos(angle) * 12.35, 0.013, sin(angle) * 12.35));
        tick.eulerAngles = SCNVector3Make(0, -angle, 0);
        tick.castsShadow = NO;
        [terrain addChildNode:tick];
    }

    // Perimeter floodlights give the plateau scale and a believable service
    // infrastructure layer without adding expensive real-time lights.
    SCNMaterial *poleMaterial = LHCPBRMaterial(LHCColor(0.18, 0.21, 0.25), 0.46, 0.62);
    SCNMaterial *lampMaterial = LHCEmissiveMaterial(LHCColor(1.0, 0.72, 0.34), 1.45);
    for (NSInteger i = 0; i < 16; i++) {
        CGFloat angle = ((CGFloat)i + 0.5) / 16.0 * M_PI * 2.0;
        CGFloat x = cosf(angle) * 12.72;
        CGFloat z = sinf(angle) * 12.72;
        [terrain addChildNode:LHCBox(SCNVector3Make(0.15, 0.035, 0.15), 0.006,
                                     poleMaterial, SCNVector3Make(x, 0.018, z))];
        [terrain addChildNode:LHCCylinder(0.026, 1.22, poleMaterial,
                                          SCNVector3Make(x, 0.64, z), NO)];
        SCNNode *head = LHCBox(SCNVector3Make(0.17, 0.065, 0.10), 0.010,
                               poleMaterial, SCNVector3Make(x, 1.28, z));
        head.eulerAngles = SCNVector3Make(0, -angle, 0);
        [terrain addChildNode:head];
        SCNNode *lens = LHCBox(SCNVector3Make(0.12, 0.035, 0.018), 0.003,
                               lampMaterial,
                               SCNVector3Make(x - cosf(angle) * 0.095, 1.27,
                                              z - sinf(angle) * 0.095));
        lens.eulerAngles = SCNVector3Make(0, -angle, 0);
        lens.castsShadow = NO;
        [terrain addChildNode:lens];
    }
}

#pragma mark Tunnel and beam guides

- (void)buildTunnel {
    SCNNode *tunnel = [SCNNode node];
    tunnel.name = @"part.vacuum";
    [self.scene.rootNode addChildNode:tunnel];
    self.tunnelNode = tunnel;

    SCNMaterial *metal = [SCNMaterial material];
    metal.lightingModelName = SCNLightingModelPhysicallyBased;
    metal.diffuse.contents = LHCPanelTexture(LHCColor(0.075, 0.13, 0.20),
                                             LHCColor(0.08, 0.48, 0.78), 16);
    metal.roughness.contents = @0.48;
    metal.metalness.contents = @0.12;
    metal.transparency = self.configuration.tunnelOpacity;
    metal.blendMode = SCNBlendModeAlpha;
    metal.doubleSided = YES;
    metal.writesToDepthBuffer = NO;
    self.tunnelMaterial = metal;

    SCNTorus *tunnelTorus = [SCNTorus torusWithRingRadius:LHCRingRadius pipeRadius:0.30];
    tunnelTorus.ringSegmentCount = 180;
    tunnelTorus.pipeSegmentCount = 30;
    tunnelTorus.materials = @[metal];
    SCNNode *tunnelPipe = [SCNNode nodeWithGeometry:tunnelTorus];
    tunnelPipe.position = SCNVector3Make(0, LHCBeamHeight, 0);
    tunnelPipe.castsShadow = NO;
    [tunnel addChildNode:tunnelPipe];

    // A darker inner cryostat makes the glassy outer tube read clearly.
    SCNMaterial *innerMaterial = LHCPBRMaterial(LHCColor(0.06, 0.10, 0.14), 0.55, 0.6);
    innerMaterial.transparency = 0.7;
    SCNTorus *innerTorus = [SCNTorus torusWithRingRadius:LHCRingRadius pipeRadius:0.18];
    innerTorus.ringSegmentCount = 180;
    innerTorus.pipeSegmentCount = 24;
    innerTorus.materials = @[innerMaterial];
    SCNNode *innerPipe = [SCNNode nodeWithGeometry:innerTorus];
    innerPipe.position = SCNVector3Make(0, LHCBeamHeight, 0);
    innerPipe.castsShadow = NO;
    [tunnel addChildNode:innerPipe];

    // Display plinths support the elevated ring.
    SCNMaterial *plinthMaterial = LHCPBRMaterial(LHCColor(0.055, 0.075, 0.10), 0.42, 0.55);
    SCNMaterial *plinthAccent = LHCEmissiveMaterial(LHCColor(0.18, 0.58, 0.86), 0.8);
    for (NSInteger i = 0; i < 12; i++) {
        CGFloat angle = (CGFloat)i / 12.0 * M_PI * 2.0;
        CGFloat x = cosf(angle) * LHCRingRadius;
        CGFloat z = sinf(angle) * LHCRingRadius;
        SCNNode *column = LHCBox(SCNVector3Make(0.34, LHCBeamHeight - 0.22, 0.5), 0.05,
                                 plinthMaterial,
                                 SCNVector3Make(x, (LHCBeamHeight - 0.22) * 0.5, z));
        column.eulerAngles = SCNVector3Make(0, -angle, 0);
        [tunnel addChildNode:column];
        SCNNode *stripe = LHCBox(SCNVector3Make(0.17, 0.018, 0.52), 0.005,
                                 plinthAccent,
                                 SCNVector3Make(x, LHCBeamHeight - 0.24, z));
        stripe.eulerAngles = SCNVector3Make(0, -angle, 0);
        stripe.castsShadow = NO;
        [tunnel addChildNode:stripe];
    }
}

- (void)buildBeamGuides {
    SCNMaterial *cyan = LHCEmissiveMaterial(LHCColor(0.16, 0.88, 1.0), 3.5);
    cyan.transparency = 1.0;
    cyan.writesToDepthBuffer = NO;
    SCNMaterial *magenta = LHCEmissiveMaterial(LHCColor(1.0, 0.20, 0.72), 3.5);
    magenta.transparency = 1.0;
    magenta.writesToDepthBuffer = NO;

    SCNNode *guideA = LHCTorus(LHCRingRadius - 0.12, 0.028, cyan,
                               SCNVector3Make(0, LHCBeamHeight, 0), NO);
    SCNNode *guideB = LHCTorus(LHCRingRadius + 0.12, 0.028, magenta,
                               SCNVector3Make(0, LHCBeamHeight, 0), NO);
    guideA.renderingOrder = 40;
    guideB.renderingOrder = 40;
    guideA.castsShadow = NO;
    guideB.castsShadow = NO;
    guideA.name = @"part.beam";
    guideB.name = @"part.beam";
    [self.scene.rootNode addChildNode:guideA];
    [self.scene.rootNode addChildNode:guideB];
}

#pragma mark Magnets

- (void)buildMagnets {
    SCNNode *magnets = [SCNNode node];
    [self.scene.rootNode addChildNode:magnets];
    self.magnetsNode = magnets;

    SCNMaterial *dipoleMaterial = LHCPanelMaterial(LHCColor(0.055, 0.29, 0.86),
                                                   LHCColor(0.28, 0.76, 1.0), 0.30, 0.62);
    SCNMaterial *dipoleEdge = LHCPBRMaterial(LHCColor(0.64, 0.71, 0.79), 0.26, 0.92);
    SCNMaterial *dipoleDark = LHCPBRMaterial(LHCColor(0.10, 0.14, 0.20), 0.38, 0.72);
    SCNMaterial *quadMaterial = LHCPanelMaterial(LHCColor(0.82, 0.055, 0.11),
                                                 LHCColor(1.0, 0.48, 0.38), 0.30, 0.58);
    SCNMaterial *quadEdge = LHCPBRMaterial(LHCColor(0.80, 0.83, 0.89), 0.24, 0.9);
    SCNMaterial *steel = LHCPBRMaterial(LHCColor(0.22, 0.26, 0.32), 0.42, 0.78);
    SCNMaterial *rfMaterial = LHCPanelMaterial(LHCColor(0.68, 0.72, 0.77),
                                               LHCColor(0.30, 0.88, 0.86), 0.23, 0.88);
    SCNMaterial *rfAccent = LHCEmissiveMaterial(LHCColor(0.32, 0.98, 0.90), 1.3);
    SCNMaterial *busBar = LHCEmissiveMaterial(LHCColor(0.35, 0.85, 1.0), 0.9);
    busBar.transparency = 0.78;
    SCNMaterial *cryoPipe = LHCPBRMaterial(LHCColor(0.72, 0.78, 0.83), 0.28, 0.86);

    // A structural girder and piers turn the magnet row into an engineered
    // accelerator lattice instead of a chain of floating boxes.
    SCNNode *girder = LHCTorus(LHCRingRadius, 0.075, steel,
                               SCNVector3Make(0, 0.30, 0), NO);
    girder.castsShadow = YES;
    [magnets addChildNode:girder];
    for (NSInteger i = 0; i < 16; i++) {
        CGFloat angle = (CGFloat)i / 16.0 * M_PI * 2.0;
        SCNNode *pier = LHCBox(SCNVector3Make(0.18, 0.30, 0.20), 0.025, steel,
                               SCNVector3Make(cosf(angle) * LHCRingRadius, 0.15,
                                              sinf(angle) * LHCRingRadius));
        pier.eulerAngles = SCNVector3Make(0, -angle, 0);
        [magnets addChildNode:pier];
        SCNNode *pierCap = LHCBox(SCNVector3Make(0.24, 0.045, 0.26), 0.012, steel,
                                  SCNVector3Make(cosf(angle) * LHCRingRadius, 0.31,
                                                 sinf(angle) * LHCRingRadius));
        pierCap.eulerAngles = SCNVector3Make(0, -angle, 0);
        [magnets addChildNode:pierCap];
    }

    NSArray<NSNumber *> *detectorAngles = @[@225.0, @315.0, @135.0, @45.0];
    const NSInteger slotCount = 64;
    const NSInteger quadrupoleInterval = 5;
    const CGFloat detectorGapDegrees = 21.0;

    for (NSInteger i = 0; i < slotCount; i++) {
        CGFloat angleDegrees = (CGFloat)i * (360.0 / (CGFloat)slotCount);
        CGFloat angle = angleDegrees * (CGFloat)M_PI / 180.0;

        BOOL nearDetector = NO;
        for (NSNumber *detectorAngle in detectorAngles) {
            CGFloat delta = fabs(angleDegrees - detectorAngle.doubleValue);
            delta = fmin(delta, 360.0 - delta);
            if (delta < detectorGapDegrees) {
                nearDetector = YES;
                break;
            }
        }
        if (nearDetector) {
            continue;
        }

        BOOL isQuadrupole = (i % quadrupoleInterval) == (quadrupoleInterval - 1);
        SCNNode *magnet = [SCNNode node];
        magnet.name = isQuadrupole ? @"part.quadrupole" : @"part.dipole";
        magnet.position = SCNVector3Make(cosf(angle) * LHCRingRadius,
                                         LHCBeamHeight,
                                         sinf(angle) * LHCRingRadius);
        magnet.eulerAngles = SCNVector3Make(0, -angle, 0);

        SCNMaterial *bodyMaterial = isQuadrupole ? quadMaterial : dipoleMaterial;
        SCNMaterial *trimMaterial = isQuadrupole ? quadEdge : dipoleEdge;
        CGFloat bodyRadius = isQuadrupole ? 0.265 : 0.305;
        CGFloat bodyLength = isQuadrupole ? 0.54 : 0.82;

        // Rounded cryostat vessel with machined end flanges.
        SCNNode *body = LHCCylinder(bodyRadius, bodyLength, bodyMaterial,
                                    SCNVector3Make(0, 0, 0), YES);
        [magnet addChildNode:body];

        for (NSInteger side = -1; side <= 1; side += 2) {
            CGFloat x = (CGFloat)side * (bodyLength * 0.5 - 0.008);
            SCNNode *flange = LHCCylinder(bodyRadius + 0.020, 0.075, trimMaterial,
                                          SCNVector3Make(x, 0, 0), YES);
            [magnet addChildNode:flange];
            SCNNode *flangeRing = LHCTorus(bodyRadius + 0.018, 0.014, trimMaterial,
                                            SCNVector3Make(x, 0, 0), YES);
            [magnet addChildNode:flangeRing];
            SCNNode *gasket = LHCTorus(bodyRadius * 0.84, 0.010, dipoleDark,
                                       SCNVector3Make(x + (CGFloat)side * 0.036, 0, 0), YES);
            [magnet addChildNode:gasket];
        }

        if (isQuadrupole) {
            // Four longitudinal coil clamps around the red cold mass.
            for (NSInteger k = 0; k < 4; k++) {
                CGFloat theta = (CGFloat)k * M_PI_2 + M_PI_4;
                SCNNode *clamp = LHCBox(SCNVector3Make(0.44, 0.028, 0.070), 0.008,
                                        trimMaterial,
                                        SCNVector3Make(0, sinf(theta) * (bodyRadius + 0.012),
                                                       cosf(theta) * (bodyRadius + 0.012)));
                clamp.eulerAngles = SCNVector3Make(theta, 0, 0);
                [magnet addChildNode:clamp];
            }
        } else {
            // Longitudinal stiffening ribs and the cryogenic supply line.
            for (NSInteger side = -1; side <= 1; side += 2) {
                SCNNode *rib = LHCBox(SCNVector3Make(bodyLength * 0.72, 0.026, 0.050),
                                      0.006, trimMaterial,
                                      SCNVector3Make(0, 0, (CGFloat)side * (bodyRadius + 0.005)));
                [magnet addChildNode:rib];
            }
            SCNNode *cooling = LHCCylinder(0.030, bodyLength * 0.84, cryoPipe,
                                           SCNVector3Make(0, bodyRadius + 0.04, 0.055), YES);
            [magnet addChildNode:cooling];
            SCNNode *cryoReturn = LHCCylinder(0.022, bodyLength * 0.76, cryoPipe,
                                              SCNVector3Make(0, bodyRadius + 0.035, -0.070), YES);
            [magnet addChildNode:cryoReturn];
        }

        // Current leads, instrumentation box and luminous busbar.
        SCNNode *leadBox = LHCBox(SCNVector3Make(isQuadrupole ? 0.16 : 0.22, 0.105, 0.20),
                                  0.015, dipoleDark,
                                  SCNVector3Make(0.04, bodyRadius + 0.085, 0));
        [magnet addChildNode:leadBox];
        SCNNode *busbar = LHCBox(SCNVector3Make(bodyLength * 0.56, 0.018, 0.035),
                                 0.004, busBar,
                                 SCNVector3Make(-0.04, bodyRadius + 0.148, 0));
        busbar.castsShadow = NO;
        [magnet addChildNode:busbar];

        // Support cradle and two jacks reach down to the circular girder.
        CGFloat cradleY = -(bodyRadius + 0.16);
        SCNNode *cradle = LHCBox(SCNVector3Make(bodyLength * 0.66, 0.075, 0.34),
                                 0.012, steel, SCNVector3Make(0, cradleY, 0));
        [magnet addChildNode:cradle];
        for (NSInteger side = -1; side <= 1; side += 2) {
            SCNNode *leg = LHCBox(SCNVector3Make(0.075, 0.31, 0.12), 0.008, steel,
                                  SCNVector3Make((CGFloat)side * bodyLength * 0.26,
                                                 cradleY - 0.17, 0));
            [magnet addChildNode:leg];
            SCNNode *foot = LHCBox(SCNVector3Make(0.15, 0.035, 0.20), 0.008, steel,
                                   SCNVector3Make((CGFloat)side * bodyLength * 0.26,
                                                  cradleY - 0.335, 0));
            [magnet addChildNode:foot];
        }

        // Short bellows bridge the gap to the next cryostat.
        SCNNode *interconnect = LHCCylinder(0.105, 0.13, dipoleDark,
                                            SCNVector3Make(bodyLength * 0.5 + 0.065, 0, 0),
                                            YES);
        [magnet addChildNode:interconnect];
        SCNNode *interconnectRing = LHCTorus(0.112, 0.012, cryoPipe,
                                              SCNVector3Make(bodyLength * 0.5 + 0.065, 0, 0),
                                              YES);
        [magnet addChildNode:interconnectRing];

        [magnets addChildNode:magnet];
    }

    // RF accelerating cavities at the four straight sections between detectors.
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat angle = (CGFloat)i * M_PI / 2.0 + M_PI_4 / 2.0;
        SCNNode *rf = [SCNNode node];
        rf.name = @"part.rf";
        rf.position = SCNVector3Make(cosf(angle) * LHCRingRadius,
                                     LHCBeamHeight,
                                     sinf(angle) * LHCRingRadius);
        rf.eulerAngles = SCNVector3Make(0, -angle, 0);

        SCNNode *outerVessel = LHCCylinder(0.275, 0.82, rfMaterial,
                                           SCNVector3Make(0, 0, 0), YES);
        [rf addChildNode:outerVessel];
        for (NSInteger j = -2; j <= 2; j++) {
            SCNNode *bellows = LHCTorus(0.286, 0.027, rfAccent,
                                        SCNVector3Make((CGFloat)j * 0.14, 0, 0), YES);
            [rf addChildNode:bellows];
        }
        for (NSInteger side = -1; side <= 1; side += 2) {
            SCNNode *rfFlange = LHCCylinder(0.305, 0.055, cryoPipe,
                                            SCNVector3Make((CGFloat)side * 0.43, 0, 0), YES);
            [rf addChildNode:rfFlange];
            SCNNode *rfRing = LHCTorus(0.302, 0.010, rfAccent,
                                        SCNVector3Make((CGFloat)side * 0.43, 0, 0), YES);
            [rf addChildNode:rfRing];
        }
        SCNNode *top = LHCBox(SCNVector3Make(0.40, 0.075, 0.22), 0.015,
                              rfAccent, SCNVector3Make(0, 0.30, 0));
        top.castsShadow = NO;
        [rf addChildNode:top];
        for (NSInteger side = -1; side <= 1; side += 2) {
            SCNNode *waveguide = LHCCylinder(0.035, 0.34, rfMaterial,
                                             SCNVector3Make((CGFloat)side * 0.20, 0.14, 0.0),
                                             NO);
            [rf addChildNode:waveguide];
            SCNNode *waveguideElbow = LHCTorus(0.10, 0.032, cryoPipe,
                                               SCNVector3Make((CGFloat)side * 0.20, 0.28, 0),
                                               NO);
            [rf addChildNode:waveguideElbow];
        }
        SCNNode *cradle = LHCBox(SCNVector3Make(0.58, 0.07, 0.34), 0.01, steel,
                                  SCNVector3Make(0, -0.33, 0));
        [rf addChildNode:cradle];
        [magnets addChildNode:rf];
    }
}

#pragma mark Detector base

- (void)addDetectorBaseToRoot:(SCNNode *)root
                        width:(CGFloat)width
                        depth:(CGFloat)depth
                       accent:(NSColor *)accent {
    SCNMaterial *baseMaterial = LHCPanelMaterial(LHCColor(0.040, 0.058, 0.085),
                                                 accent, 0.32, 0.55);
    SCNMaterial *deckMaterial = LHCPanelMaterial(LHCColor(0.085, 0.105, 0.135),
                                                 LHCColor(0.24, 0.31, 0.38), 0.48, 0.55);
    SCNMaterial *accentMaterial = LHCEmissiveMaterial(accent, 1.0);
    SCNMaterial *railMaterial = LHCPBRMaterial(LHCColor(0.40, 0.46, 0.53), 0.25, 0.92);
    SCNMaterial *darkSteel = LHCPBRMaterial(LHCColor(0.15, 0.18, 0.22), 0.44, 0.72);
    SCNMaterial *warning = LHCPanelMaterial(LHCColor(0.88, 0.60, 0.11),
                                             LHCColor(0.10, 0.08, 0.04), 0.5, 0.22);

    // Concrete footing, structural steel skirt and a bolted service deck.
    SCNNode *footing = LHCBox(SCNVector3Make(width + 0.42, 0.075, depth + 0.42), 0.025,
                              LHCPBRMaterial(LHCColor(0.17, 0.18, 0.19), 0.88, 0.02),
                              SCNVector3Make(0, 0.0375, 0));
    [root addChildNode:footing];
    SCNNode *plinth = LHCBox(SCNVector3Make(width + 0.25, 0.14, depth + 0.25), 0.05,
                             baseMaterial, SCNVector3Make(0, 0.145, 0));
    [root addChildNode:plinth];
    SCNNode *deck = LHCBox(SCNVector3Make(width, 0.095, depth), 0.028,
                           deckMaterial, SCNVector3Make(0, 0.25, 0));
    [root addChildNode:deck];

    // Raised rim with a fine glowing edge.
    SCNNode *rim = LHCBox(SCNVector3Make(width + 0.10, 0.035, depth + 0.10), 0.012,
                          darkSteel, SCNVector3Make(0, 0.21, 0));
    [root addChildNode:rim];

    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *accentStrip = LHCBox(SCNVector3Make(width * 0.72, 0.014, 0.025), 0.003,
                                      accentMaterial,
                                      SCNVector3Make(0, 0.305, (CGFloat)side * depth * 0.5));
        accentStrip.castsShadow = NO;
        [root addChildNode:accentStrip];

        SCNNode *rail = LHCBox(SCNVector3Make(width + 0.20, 0.045, 0.06), 0.006,
                               railMaterial,
                               SCNVector3Make(0, 0.055, (CGFloat)side * (depth * 0.5 + 0.14)));
        [root addChildNode:rail];

        // Yellow-black toe board and a horizontal cable tray along the sides.
        SCNNode *toeBoard = LHCBox(SCNVector3Make(width * 0.96, 0.065, 0.022), 0.004,
                                   warning,
                                   SCNVector3Make(0, 0.13, (CGFloat)side * (depth * 0.5 + 0.135)));
        [root addChildNode:toeBoard];
        SCNNode *cableTray = LHCBox(SCNVector3Make(width * 0.78, 0.045, 0.12), 0.008,
                                    darkSteel,
                                    SCNVector3Make(0, 0.085, (CGFloat)side * (depth * 0.5 + 0.02)));
        [root addChildNode:cableTray];
    }

    // Perimeter handrails: posts, top rail and a mid rail.
    CGFloat railHeight = 0.52;
    for (NSInteger side = -1; side <= 1; side += 2) {
        for (NSInteger end = -1; end <= 1; end += 2) {
            CGFloat x = (CGFloat)side * (width * 0.5 - 0.04);
            CGFloat z = (CGFloat)end * (depth * 0.5 - 0.04);
            SCNNode *post = LHCBox(SCNVector3Make(0.035, railHeight, 0.035), 0.006,
                                   railMaterial,
                                   SCNVector3Make(x, 0.30 + railHeight * 0.5, z));
            [root addChildNode:post];
        }
        for (NSInteger end = 0; end <= 1; end++) {
            CGFloat z = (CGFloat)(end == 0 ? -1 : 1) * (depth * 0.5 - 0.04);
            SCNNode *topRail = LHCBox(SCNVector3Make(width - 0.08, 0.028, 0.028), 0.005,
                                      railMaterial,
                                      SCNVector3Make(0, 0.30 + railHeight, z));
            [root addChildNode:topRail];
            SCNNode *midRail = LHCBox(SCNVector3Make(width - 0.08, 0.016, 0.016), 0.003,
                                      railMaterial,
                                      SCNVector3Make(0, 0.30 + railHeight * 0.52, z));
            [root addChildNode:midRail];
        }
    }
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *sideTopRail = LHCBox(SCNVector3Make(0.028, 0.028, depth - 0.08), 0.005,
                                      railMaterial,
                                      SCNVector3Make((CGFloat)side * (width * 0.5 - 0.04),
                                                     0.30 + railHeight, 0));
        [root addChildNode:sideTopRail];
    }

    // Low service cabinets leave the detector silhouette readable while
    // adding believable equipment density around the experiment.
    for (NSInteger side = -1; side <= 1; side += 2) {
        CGFloat x = (CGFloat)side * (width * 0.5 - 0.18);
        CGFloat z = -(depth * 0.5 - 0.20);
        SCNNode *cabinet = LHCBox(SCNVector3Make(0.30, 0.44, 0.24), 0.018,
                                  LHCPanelMaterial(LHCColor(0.085, 0.11, 0.14),
                                                   accent, 0.42, 0.5),
                                  SCNVector3Make(x, 0.52, z));
        [root addChildNode:cabinet];
        for (NSInteger row = 0; row < 3; row++) {
            SCNNode *vent = LHCBox(SCNVector3Make(0.20, 0.009, 0.014), 0.002,
                                   darkSteel,
                                   SCNVector3Make(x, 0.41 + (CGFloat)row * 0.035,
                                                  z + 0.125));
            vent.castsShadow = NO;
            [root addChildNode:vent];
        }
        SCNNode *status = LHCBox(SCNVector3Make(0.055, 0.012, 0.012), 0.002,
                                 accentMaterial,
                                 SCNVector3Make(x + 0.075, 0.68, z + 0.125));
        status.castsShadow = NO;
        [root addChildNode:status];
    }

    // Front steps make the platform feel accessible at human scale.
    for (NSInteger step = 0; step < 2; step++) {
        SCNNode *tread = LHCBox(SCNVector3Make(0.72, 0.045, 0.20 - (CGFloat)step * 0.02),
                                0.008, darkSteel,
                                SCNVector3Make(0, 0.17 - (CGFloat)step * 0.06,
                                               depth * 0.5 + 0.30 - (CGFloat)step * 0.18));
        [root addChildNode:tread];
    }

    // Corner pads / feet.
    for (NSInteger sx = -1; sx <= 1; sx += 2) {
        for (NSInteger sz = -1; sz <= 1; sz += 2) {
            SCNNode *foot = LHCBox(SCNVector3Make(0.18, 0.055, 0.18), 0.012,
                                   railMaterial,
                                   SCNVector3Make((CGFloat)sx * (width * 0.5 - 0.16), 0.0275,
                                                  (CGFloat)sz * (depth * 0.5 - 0.16)));
            [root addChildNode:foot];
        }
    }
}

- (SCNNode *)newOuterShellForRoot:(SCNNode *)root {
    SCNNode *shell = [SCNNode node];
    shell.name = @"outerShell";
    [root addChildNode:shell];
    [self.outerShells addObject:shell];
    return shell;
}

- (void)addDetectorLabelForIdentifier:(NSString *)identifier
                                  name:(NSString *)name
                                accent:(NSColor *)accent
                                height:(CGFloat)height
                      worldPosition:(SCNVector3)worldPosition {
    NSImage *image = LHCLabelImage(name, accent);
    CGFloat planeHeight = 0.47;
    CGFloat planeWidth = planeHeight * (image.size.width / image.size.height);

    SCNPlane *plane = [SCNPlane planeWithWidth:planeWidth height:planeHeight];
    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelConstant;
    material.diffuse.contents = image;
    material.emission.contents = image;
    material.emission.intensity = 0.38;
    material.doubleSided = YES;
    material.writesToDepthBuffer = NO;
    material.blendMode = SCNBlendModeAlpha;
    plane.materials = @[material];

    SCNNode *label = [SCNNode nodeWithGeometry:plane];
    label.name = [@"part." stringByAppendingString:identifier];
    label.position = SCNVector3Make(worldPosition.x, height, worldPosition.z);
    SCNBillboardConstraint *billboard = [SCNBillboardConstraint billboardConstraint];
    billboard.freeAxes = SCNBillboardAxisAll;
    label.constraints = @[billboard];
    label.castsShadow = NO;
    label.categoryBitMask = 1 << 3;
    [self.labelsRoot addChildNode:label];
    [self.labelNodes addObject:label];
}

#pragma mark ATLAS

- (SCNNode *)buildATLAS {
    SCNNode *root = [SCNNode node];
    root.name = @"part.atlas";
    NSColor *accent = LHCColor(0.35, 0.66, 1.0);
    [self addDetectorBaseToRoot:root width:3.9 depth:2.95 accent:accent];

    SCNMaterial *silver = LHCPBRMaterial(LHCColor(0.66, 0.72, 0.79), 0.22, 0.94);
    SCNMaterial *polished = LHCPBRMaterial(LHCColor(0.80, 0.84, 0.88), 0.16, 0.98);
    SCNMaterial *darkSilver = LHCPBRMaterial(LHCColor(0.28, 0.33, 0.39), 0.30, 0.84);
    SCNMaterial *blue = LHCPanelMaterial(LHCColor(0.075, 0.245, 0.68), accent, 0.26, 0.66);
    SCNMaterial *blueDeep = LHCPBRMaterial(LHCColor(0.045, 0.14, 0.36), 0.28, 0.68);
    SCNMaterial *copper = LHCPanelMaterial(LHCColor(0.55, 0.27, 0.10),
                                           LHCColor(0.98, 0.58, 0.24), 0.30, 0.74);
    SCNMaterial *gold = LHCPBRMaterial(LHCColor(0.86, 0.64, 0.23), 0.19, 0.94);
    SCNMaterial *cyanGlow = LHCEmissiveMaterial(LHCColor(0.26, 0.88, 1.0), 1.6);

    // Beam pipe runs straight through every sub-detector.
    [root addChildNode:LHCCylinder(0.040, 3.85, polished,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = -2; i <= 2; i++) {
        if (i == 0) continue;
        SCNNode *flange = LHCCylinder(0.075, 0.035, silver,
                                      SCNVector3Make((CGFloat)i * 0.78,
                                                     LHCBeamHeight, 0), YES);
        [root addChildNode:flange];
        [root addChildNode:LHCTorus(0.072, 0.010, darkSilver,
                                    SCNVector3Make((CGFloat)i * 0.78,
                                                   LHCBeamHeight, 0), YES)];
    }

    // Silicon tracker: nested barrels with end-cap disks and service rings.
    SCNMaterial *trackerMaterial = LHCPBRMaterial(LHCColor(0.12, 0.29, 0.48), 0.34, 0.55);
    [root addChildNode:LHCCylinder(0.145, 1.34, trackerMaterial,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat radius = 0.17 + (CGFloat)i * 0.045;
        SCNMaterial *layerMaterial = LHCEmissiveMaterial(i == 1 ? cyanGlow.diffuse.contents : accent, 0.55);
        layerMaterial.transparency = 0.30;
        SCNNode *layer = LHCCylinder(radius, 1.28, layerMaterial,
                                     SCNVector3Make(0, LHCBeamHeight, 0), YES);
        layer.castsShadow = NO;
        [root addChildNode:layer];
        for (NSInteger side = -1; side <= 1; side += 2) {
            SCNNode *disk = LHCCylinder(radius + 0.012, 0.022, gold,
                                        SCNVector3Make((CGFloat)side * 0.64,
                                                       LHCBeamHeight, 0), YES);
            disk.castsShadow = NO;
            [root addChildNode:disk];
        }
    }
    for (NSInteger i = 0; i < 12; i++) {
        CGFloat angle = (CGFloat)i / 12.0 * M_PI * 2.0;
        SCNNode *module = LHCBox(SCNVector3Make(0.045, 0.12, 0.035), 0.004, gold,
                                 SCNVector3Make(0.09, LHCBeamHeight + cosf(angle) * 0.30,
                                                sinf(angle) * 0.30));
        module.eulerAngles = SCNVector3Make(angle, 0, 0);
        module.castsShadow = NO;
        [root addChildNode:module];
    }

    // Solenoid, LAr barrel and tile calorimeter are nested so the cutaway
    // view reads as a real detector cross-section.
    [root addChildNode:LHCCylinder(0.285, 1.58, polished,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = -3; i <= 3; i++) {
        [root addChildNode:LHCTorus(0.292, 0.010, silver,
                                    SCNVector3Make((CGFloat)i * 0.22,
                                                   LHCBeamHeight, 0), YES)];
    }
    [root addChildNode:LHCCylinder(0.405, 1.90, silver,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = -4; i <= 4; i++) {
        SCNNode *coilRib = LHCTorus(0.414, 0.012, darkSilver,
                                    SCNVector3Make((CGFloat)i * 0.19,
                                                   LHCBeamHeight, 0), YES);
        [root addChildNode:coilRib];
    }
    [root addChildNode:LHCCylinder(0.515, 1.78, copper,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = -1; i <= 1; i += 2) {
        [root addChildNode:LHCCylinder(0.535, 0.075, gold,
                                       SCNVector3Make((CGFloat)i * 0.86,
                                                      LHCBeamHeight, 0), YES)];
    }
    [root addChildNode:LHCCylinder(0.625, 2.05, darkSilver,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = 0; i < 12; i++) {
        CGFloat angle = (CGFloat)i / 12.0 * M_PI * 2.0;
        SCNNode *tileRib = LHCBox(SCNVector3Make(0.035, 0.11, 0.10), 0.006, silver,
                                  SCNVector3Make(0, LHCBeamHeight + cosf(angle) * 0.66,
                                                 sinf(angle) * 0.66));
        tileRib.eulerAngles = SCNVector3Make(angle, 0, 0);
        [root addChildNode:tileRib];
    }

    SCNNode *shell = [self newOuterShellForRoot:root];

    // Blue cryostat barrel with machined end rings.
    [shell addChildNode:LHCCylinder(0.795, 2.38, blue,
                                    SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = -1; i <= 1; i += 2) {
        [shell addChildNode:LHCCylinder(0.815, 0.10, blueDeep,
                                        SCNVector3Make((CGFloat)i * 1.06,
                                                       LHCBeamHeight, 0), YES)];
        [shell addChildNode:LHCTorus(0.812, 0.030, silver,
                                     SCNVector3Make((CGFloat)i * 1.11,
                                                    LHCBeamHeight, 0), YES)];
    }

    // Eight true race-track barrel toroid coils (hollow extruded loops).
    SCNNode *barrelToroid = [SCNNode node];
    barrelToroid.position = SCNVector3Make(0, LHCBeamHeight, 0);
    [shell addChildNode:barrelToroid];
    for (NSInteger i = 0; i < 8; i++) {
        SCNNode *coilHolder = [SCNNode node];
        coilHolder.eulerAngles = SCNVector3Make((CGFloat)i * M_PI_4, 0, 0);
        [barrelToroid addChildNode:coilHolder];
        SCNNode *coil = LHCRoundedLoop(2.56, 1.66, 0.38, 0.145, 0.155,
                                       blue, SCNVector3Zero);
        [coilHolder addChildNode:coil];
    }

    // Toroid support frames: radial struts and two continuous rings.
    for (NSInteger side = -1; side <= 1; side += 2) {
        CGFloat x = (CGFloat)side * 1.00;
        [shell addChildNode:LHCTorus(0.90, 0.030, silver,
                                     SCNVector3Make(x, LHCBeamHeight, 0), YES)];
        for (NSInteger i = 0; i < 8; i++) {
            CGFloat theta = (CGFloat)i * M_PI_4;
            SCNNode *strut = LHCBox(SCNVector3Make(0.040, 0.30, 0.040), 0.008,
                                    darkSilver,
                                    SCNVector3Make(x, LHCBeamHeight + cosf(theta) * 0.80,
                                                   sinf(theta) * 0.80));
            strut.eulerAngles = SCNVector3Make(theta, 0, 0);
            [shell addChildNode:strut];
        }
    }

    // End-cap toroids: eight annular sectors per side with the characteristic
    // open gaps between the coils.
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *endCap = [SCNNode node];
        endCap.position = SCNVector3Make((CGFloat)side * 1.34, LHCBeamHeight, 0);
        [shell addChildNode:endCap];
        for (NSInteger i = 0; i < 8; i++) {
            CGFloat start = (CGFloat)i * 45.0 + 2.2;
            SCNNode *sector = LHCRingSector(0.53, 0.96, start, start + 40.2,
                                            0.20, blue, SCNVector3Zero);
            sector.position = SCNVector3Zero;
            sector.eulerAngles = SCNVector3Make(0, M_PI_2, 0);
            [endCap addChildNode:sector];
        }
        [shell addChildNode:LHCTorus(0.97, 0.025, silver,
                                     SCNVector3Make((CGFloat)side * 1.44,
                                                    LHCBeamHeight, 0), YES)];
        [shell addChildNode:LHCTorus(0.52, 0.020, gold,
                                     SCNVector3Make((CGFloat)side * 1.44,
                                                    LHCBeamHeight, 0), YES)];

        // The end-cap toroid has a large central aperture. Fill it with the
        // segmented LAr end-cap calorimeter and tracker disk instead of
        // leaving a hollow tube through the detector.
        for (NSInteger sectorIndex = 0; sectorIndex < 12; sectorIndex++) {
            CGFloat start = (CGFloat)sectorIndex * 30.0 + 1.0;
            SCNNode *caloSector = LHCRingSector(0.11, 0.505, start, start + 28.0,
                                                0.11, copper, SCNVector3Zero);
            caloSector.position = SCNVector3Make((CGFloat)side * 1.27,
                                                 LHCBeamHeight, 0);
            caloSector.eulerAngles = SCNVector3Make(0, M_PI_2, 0);
            caloSector.geometry.firstMaterial.doubleSided = YES;
            [shell addChildNode:caloSector];
        }
        for (NSInteger ringIndex = 0; ringIndex < 3; ringIndex++) {
            CGFloat radius = 0.18 + (CGFloat)ringIndex * 0.12;
            [shell addChildNode:LHCTorus(radius, 0.008, silver,
                                          SCNVector3Make((CGFloat)side * 1.330,
                                                         LHCBeamHeight, 0), YES)];
        }
        for (NSInteger ribIndex = 0; ribIndex < 12; ribIndex++) {
            CGFloat theta = (CGFloat)ribIndex / 12.0 * M_PI * 2.0;
            SCNNode *rib = LHCBox(SCNVector3Make(0.020, 0.38, 0.020), 0.004,
                                  darkSilver,
                                  SCNVector3Make((CGFloat)side * 1.330,
                                                 LHCBeamHeight + cosf(theta) * 0.31,
                                                 sinf(theta) * 0.31));
            rib.eulerAngles = SCNVector3Make(theta, 0, 0);
            [shell addChildNode:rib];
        }
        for (NSInteger sectorIndex = 0; sectorIndex < 8; sectorIndex++) {
            CGFloat start = (CGFloat)sectorIndex * 45.0 + 1.5;
            SCNNode *trackerSector = LHCRingSector(0.06, 0.24, start, start + 42.0,
                                                   0.055, gold, SCNVector3Zero);
            trackerSector.position = SCNVector3Make((CGFloat)side * 1.03,
                                                    LHCBeamHeight, 0);
            trackerSector.eulerAngles = SCNVector3Make(0, M_PI_2, 0);
            trackerSector.geometry.firstMaterial.doubleSided = YES;
            [shell addChildNode:trackerSector];
        }

        // Two end-cap muon wheels, each built from 12 chambers.
        for (NSInteger wheel = 0; wheel < 2; wheel++) {
            CGFloat wheelX = (CGFloat)side * (1.55 + (CGFloat)wheel * 0.16);
            SCNNode *muonWheel = [SCNNode node];
            muonWheel.position = SCNVector3Make(wheelX, LHCBeamHeight, 0);
            [shell addChildNode:muonWheel];
            [muonWheel addChildNode:LHCTorus(0.92, 0.025, silver,
                                              SCNVector3Zero, YES)];
            for (NSInteger j = 0; j < 12; j++) {
                CGFloat theta = (CGFloat)j / 12.0 * M_PI * 2.0;
                SCNNode *chamber = [SCNNode node];
                chamber.eulerAngles = SCNVector3Make(theta, 0, 0);
                [muonWheel addChildNode:chamber];
                SCNNode *plate = LHCBox(SCNVector3Make(0.115, 0.17, 0.38), 0.012,
                                        silver, SCNVector3Make(0, 0.78, 0));
                [chamber addChildNode:plate];
                SCNNode *slot = LHCBox(SCNVector3Make(0.13, 0.025, 0.30), 0.004,
                                       cyanGlow, SCNVector3Make(0, 0.78, 0));
                slot.castsShadow = NO;
                [chamber addChildNode:slot];
            }
        }
    }

    // Barrel muon stations sit just outside the toroid.
    for (NSInteger i = 0; i < 12; i++) {
        CGFloat theta = (CGFloat)i / 12.0 * M_PI * 2.0;
        for (NSInteger station = -1; station <= 1; station += 1) {
            CGFloat x = (CGFloat)station * 0.87;
            SCNNode *chamber = LHCBox(SCNVector3Make(0.36, 0.16, 0.24), 0.015,
                                      darkSilver,
                                      SCNVector3Make(x, LHCBeamHeight + cosf(theta) * 0.98,
                                                     sinf(theta) * 0.98));
            chamber.eulerAngles = SCNVector3Make(theta, 0, 0);
            [shell addChildNode:chamber];
        }
    }

    // Heavy A-frame supports and cryogenic distribution pipes.
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *support = LHCBox(SCNVector3Make(0.12, 0.52, 0.16), 0.015,
                                  darkSilver,
                                  SCNVector3Make((CGFloat)side * 1.05, 0.54, 0));
        [root addChildNode:support];
        SCNNode *supportFoot = LHCBox(SCNVector3Make(0.36, 0.055, 0.44), 0.012,
                                      darkSilver,
                                      SCNVector3Make((CGFloat)side * 1.05, 0.31, 0));
        [root addChildNode:supportFoot];
    }
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *cryo = LHCCylinder(0.030, 1.15, polished,
                                    SCNVector3Make(0, LHCBeamHeight + 1.01,
                                                   (CGFloat)side * 0.31), YES);
        [shell addChildNode:cryo];
        SCNNode *elbow = LHCTorus(0.12, 0.030, polished,
                                   SCNVector3Make((CGFloat)side * 0.56,
                                                  LHCBeamHeight + 0.90, 0.31), YES);
        [shell addChildNode:elbow];
    }

    SCNMaterial *supportGlow = LHCEmissiveMaterial(accent, 1.0);
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *glow = LHCBox(SCNVector3Make(0.06, 0.48, 0.05), 0.008,
                               supportGlow,
                               SCNVector3Make((CGFloat)side * 1.05, 0.61, 0.16));
        glow.castsShadow = NO;
        [root addChildNode:glow];
    }

    return root;
}

#pragma mark CMS

- (SCNNode *)buildCMS {
    SCNNode *root = [SCNNode node];
    root.name = @"part.cms";
    NSColor *accent = LHCColor(0.94, 0.27, 0.30);
    [self addDetectorBaseToRoot:root width:3.75 depth:3.05 accent:accent];

    SCNMaterial *silver = LHCPBRMaterial(LHCColor(0.72, 0.76, 0.81), 0.21, 0.94);
    SCNMaterial *polished = LHCPBRMaterial(LHCColor(0.84, 0.87, 0.90), 0.15, 0.98);
    SCNMaterial *red = LHCPanelMaterial(LHCColor(0.68, 0.055, 0.075), accent, 0.27, 0.58);
    SCNMaterial *redDeep = LHCPBRMaterial(LHCColor(0.31, 0.025, 0.035), 0.40, 0.52);
    SCNMaterial *steel = LHCPBRMaterial(LHCColor(0.25, 0.29, 0.34), 0.30, 0.88);
    SCNMaterial *blue = LHCPBRMaterial(LHCColor(0.08, 0.31, 0.72), 0.26, 0.58);
    SCNMaterial *gold = LHCPBRMaterial(LHCColor(0.84, 0.64, 0.27), 0.24, 0.84);
    SCNMaterial *bronze = LHCPanelMaterial(LHCColor(0.42, 0.29, 0.16),
                                            LHCColor(0.89, 0.61, 0.27), 0.38, 0.58);
    SCNMaterial *teal = LHCEmissiveMaterial(LHCColor(0.30, 0.86, 1.0), 1.35);

    [root addChildNode:LHCCylinder(0.042, 4.15, polished,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = -2; i <= 2; i++) {
        if (i == 0) continue;
        [root addChildNode:LHCCylinder(0.075, 0.032, silver,
                                       SCNVector3Make((CGFloat)i * 0.82,
                                                      LHCBeamHeight, 0), YES)];
    }
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *mount = LHCBox(SCNVector3Make(0.50, 0.55, 0.74), 0.045, steel,
                                SCNVector3Make((CGFloat)side * 0.80, 0.57, 0));
        [root addChildNode:mount];
        SCNNode *mountFoot = LHCBox(SCNVector3Make(0.72, 0.06, 0.90), 0.012, steel,
                                    SCNVector3Make((CGFloat)side * 0.80, 0.315, 0));
        [root addChildNode:mountFoot];
    }

    // Tracker, electromagnetic calorimeter and hadron calorimeter.
    [root addChildNode:LHCCylinder(0.17, 1.35, blue,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = 0; i < 3; i++) {
        SCNMaterial *layer = LHCEmissiveMaterial(i == 1 ? teal.emission.contents : accent, 0.50);
        layer.transparency = 0.28;
        SCNNode *barrel = LHCCylinder(0.195 + (CGFloat)i * 0.035, 1.24, layer,
                                      SCNVector3Make(0, LHCBeamHeight, 0), YES);
        barrel.castsShadow = NO;
        [root addChildNode:barrel];
    }
    [root addChildNode:LHCCylinder(0.335, 1.55, gold,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = -2; i <= 2; i++) {
        [root addChildNode:LHCTorus(0.342, 0.010, polished,
                                    SCNVector3Make((CGFloat)i * 0.30,
                                                   LHCBeamHeight, 0), YES)];
    }
    [root addChildNode:LHCCylinder(0.50, 1.82, bronze,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    [root addChildNode:LHCCylinder(0.64, 2.02, steel,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];

    // Solenoid with a visible high-field coil pack.
    [root addChildNode:LHCCylinder(0.73, 2.12, silver,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = -5; i <= 5; i++) {
        [root addChildNode:LHCTorus(0.738, 0.010, polished,
                                    SCNVector3Make((CGFloat)i * 0.17,
                                                   LHCBeamHeight, 0), YES)];
    }
    for (NSInteger side = -1; side <= 1; side += 2) {
        [root addChildNode:LHCTorus(0.74, 0.045, steel,
                                    SCNVector3Make((CGFloat)side * 1.03,
                                                   LHCBeamHeight, 0), YES)];
        [root addChildNode:LHCCylinder(0.80, 0.055, steel,
                                       SCNVector3Make((CGFloat)side * 1.07,
                                                      LHCBeamHeight, 0), YES)];
    }

    SCNNode *shell = [self newOuterShellForRoot:root];

    // Red iron yoke barrel, split into five precision-aligned modules.
    [shell addChildNode:LHCCylinder(0.845, 2.10, steel,
                                    SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = 0; i < 5; i++) {
        CGFloat x = -0.84 + (CGFloat)i * 0.42;
        SCNNode *barrel = LHCCylinder(0.945, 0.39, red,
                                      SCNVector3Make(x, LHCBeamHeight, 0), YES);
        [shell addChildNode:barrel];
        [shell addChildNode:LHCCylinder(0.962, 0.028, polished,
                                        SCNVector3Make(x + 0.195,
                                                       LHCBeamHeight, 0), YES)];
    }

    // Longitudinal iron yoke ribs.
    for (NSInteger i = 0; i < 12; i++) {
        CGFloat theta = (CGFloat)i / 12.0 * M_PI * 2.0;
        SCNNode *rib = LHCBox(SCNVector3Make(1.88, 0.055, 0.16), 0.012,
                              steel,
                              SCNVector3Make(0, LHCBeamHeight + cosf(theta) * 0.95,
                                             sinf(theta) * 0.95));
        rib.eulerAngles = SCNVector3Make(theta, 0, 0);
        [shell addChildNode:rib];
    }

    // End-cap yoke, muon wheels and forward stations.
    for (NSInteger side = -1; side <= 1; side += 2) {
        [shell addChildNode:LHCCylinder(1.02, 0.12, redDeep,
                                        SCNVector3Make((CGFloat)side * 1.10,
                                                       LHCBeamHeight, 0), YES)];
        [shell addChildNode:LHCTorus(1.02, 0.035, polished,
                                     SCNVector3Make((CGFloat)side * 1.16,
                                                    LHCBeamHeight, 0), YES)];
        [shell addChildNode:LHCTorus(0.60, 0.025, teal,
                                     SCNVector3Make((CGFloat)side * 1.16,
                                                    LHCBeamHeight, 0), YES)];

        for (NSInteger wheel = 0; wheel < 2; wheel++) {
            SCNNode *muonWheel = [SCNNode node];
            muonWheel.position = SCNVector3Make((CGFloat)side * (1.25 + (CGFloat)wheel * 0.20),
                                                LHCBeamHeight, 0);
            [shell addChildNode:muonWheel];
            [muonWheel addChildNode:LHCTorus(0.98, 0.024, silver,
                                              SCNVector3Zero, YES)];
            for (NSInteger j = 0; j < 12; j++) {
                CGFloat theta = (CGFloat)j / 12.0 * M_PI * 2.0;
                SCNNode *chamber = [SCNNode node];
                chamber.eulerAngles = SCNVector3Make(theta, 0, 0);
                [muonWheel addChildNode:chamber];
                SCNNode *plate = LHCBox(SCNVector3Make(0.12, 0.18, 0.31), 0.012,
                                        silver, SCNVector3Make(0, 0.84, 0));
                [chamber addChildNode:plate];
                SCNNode *slot = LHCBox(SCNVector3Make(0.135, 0.022, 0.24), 0.004,
                                       teal, SCNVector3Make(0, 0.84, 0));
                slot.castsShadow = NO;
                [chamber addChildNode:slot];
            }
        }
    }

    // Service rails, cable trays and support feet.
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *leg = LHCBox(SCNVector3Make(0.11, 0.60, 0.15), 0.012, steel,
                              SCNVector3Make((CGFloat)side * 0.83, 0.61, 0));
        [root addChildNode:leg];
        SCNNode *foot = LHCBox(SCNVector3Make(0.32, 0.055, 0.44), 0.012, steel,
                               SCNVector3Make((CGFloat)side * 0.83, 0.315, 0));
        [root addChildNode:foot];
        SCNNode *cryo = LHCCylinder(0.032, 1.1, polished,
                                    SCNVector3Make(0, LHCBeamHeight + 0.75,
                                                   (CGFloat)side * 0.38), YES);
        [shell addChildNode:cryo];
    }

    return root;
}

#pragma mark ALICE

- (SCNNode *)buildALICE {
    SCNNode *root = [SCNNode node];
    root.name = @"part.alice";
    NSColor *accent = LHCColor(0.96, 0.74, 0.23);
    [self addDetectorBaseToRoot:root width:4.7 depth:2.65 accent:accent];

    SCNMaterial *silver = LHCPBRMaterial(LHCColor(0.66, 0.71, 0.76), 0.24, 0.92);
    SCNMaterial *polished = LHCPBRMaterial(LHCColor(0.80, 0.83, 0.87), 0.17, 0.96);
    SCNMaterial *yellow = LHCPanelMaterial(LHCColor(0.74, 0.54, 0.085), accent, 0.28, 0.56);
    SCNMaterial *yellowDeep = LHCPBRMaterial(LHCColor(0.40, 0.27, 0.035), 0.36, 0.52);
    SCNMaterial *green = LHCPanelMaterial(LHCColor(0.11, 0.39, 0.21),
                                          LHCColor(0.33, 0.93, 0.54), 0.31, 0.48);
    SCNMaterial *red = LHCPBRMaterial(LHCColor(0.72, 0.085, 0.09), 0.30, 0.55);
    SCNMaterial *blue = LHCPBRMaterial(LHCColor(0.075, 0.31, 0.72), 0.25, 0.62);
    SCNMaterial *bronze = LHCPanelMaterial(LHCColor(0.40, 0.28, 0.155),
                                           LHCColor(0.78, 0.54, 0.22), 0.36, 0.62);
    SCNMaterial *steel = LHCPBRMaterial(LHCColor(0.26, 0.30, 0.35), 0.32, 0.84);
    SCNMaterial *glow = LHCEmissiveMaterial(LHCColor(0.35, 0.94, 0.62), 1.3);
    SCNMaterial *accentGlow = LHCEmissiveMaterial(accent, 1.15);

    [root addChildNode:LHCCylinder(0.040, 4.35, polished,
                                   SCNVector3Make(0.10, LHCBeamHeight, 0), YES)];
    for (NSInteger i = -2; i <= 2; i++) {
        [root addChildNode:LHCCylinder(0.068, 0.030, silver,
                                       SCNVector3Make(0.10 + (CGFloat)i * 0.82,
                                                      LHCBeamHeight, 0), YES)];
    }

    // ITS and TPC: the TPC is deliberately translucent so its field cage
    // remains legible inside the L3 magnet.
    [root addChildNode:LHCCylinder(0.16, 1.52, blue,
                                   SCNVector3Make(-0.42, LHCBeamHeight, 0), YES)];
    for (NSInteger i = 0; i < 4; i++) {
        SCNMaterial *itsLayer = LHCEmissiveMaterial(i % 2 == 0 ? glow.emission.contents : accent, 0.45);
        itsLayer.transparency = 0.32;
        SCNNode *layer = LHCCylinder(0.185 + (CGFloat)i * 0.035, 1.42, itsLayer,
                                     SCNVector3Make(-0.42, LHCBeamHeight, 0), YES);
        layer.castsShadow = NO;
        [root addChildNode:layer];
    }
    SCNMaterial *tpcMaterial = LHCPBRMaterial(LHCColor(0.12, 0.23, 0.35), 0.18, 0.25);
    tpcMaterial.transparency = 0.48;
    tpcMaterial.blendMode = SCNBlendModeAlpha;
    SCNNode *tpc = LHCCylinder(0.49, 1.58, tpcMaterial,
                               SCNVector3Make(-0.42, LHCBeamHeight, 0), YES);
    tpc.castsShadow = NO;
    [root addChildNode:tpc];
    for (NSInteger i = -3; i <= 3; i++) {
        SCNNode *fieldCage = LHCTorus(0.502, 0.010, glow,
                                      SCNVector3Make(-0.42 + (CGFloat)i * 0.24,
                                                     LHCBeamHeight, 0), YES);
        fieldCage.castsShadow = NO;
        [root addChildNode:fieldCage];
    }
    for (NSInteger i = -1; i <= 1; i += 2) {
        [root addChildNode:LHCCylinder(0.52, 0.045, polished,
                                       SCNVector3Make(-0.42 + (CGFloat)i * 0.80,
                                                      LHCBeamHeight, 0), YES)];
    }

    SCNNode *shell = [self newOuterShellForRoot:root];

    // L3 magnet: eight visible coil gaps around a segmented yellow yoke.
    [shell addChildNode:LHCCylinder(0.88, 1.60, yellow,
                                    SCNVector3Make(-0.42, LHCBeamHeight, 0), YES)];
    for (NSInteger i = 0; i < 8; i++) {
        CGFloat theta = (CGFloat)i / 8.0 * M_PI * 2.0;
        SCNNode *gap = LHCBox(SCNVector3Make(1.48, 0.035, 0.075), 0.006,
                              yellowDeep,
                              SCNVector3Make(-0.42, LHCBeamHeight + cosf(theta) * 0.89,
                                             sinf(theta) * 0.89));
        gap.eulerAngles = SCNVector3Make(theta, 0, 0);
        [shell addChildNode:gap];
    }
    for (NSInteger side = -1; side <= 1; side += 2) {
        [shell addChildNode:LHCCylinder(0.91, 0.12, green,
                                        SCNVector3Make(-0.42 + (CGFloat)side * 0.84,
                                                       LHCBeamHeight, 0), YES)];
        [shell addChildNode:LHCTorus(0.90, 0.032, red,
                                     SCNVector3Make(-0.42 + (CGFloat)side * 0.62,
                                                    LHCBeamHeight, 0), YES)];
        [shell addChildNode:LHCTorus(0.92, 0.018, polished,
                                     SCNVector3Make(-0.42 + (CGFloat)side * 0.91,
                                                    LHCBeamHeight, 0), YES)];
    }

    // PHOS: individual lead-tungstate crystals inside a metal frame.
    SCNMaterial *phos = LHCPanelMaterial(LHCColor(0.89, 0.71, 0.17),
                                         LHCColor(1.0, 0.92, 0.48), 0.24, 0.64);
    SCNNode *phosSupport = LHCBox(SCNVector3Make(1.42, 0.10, 0.72), 0.018, steel,
                                   SCNVector3Make(-0.82, 1.82, 0));
    [shell addChildNode:phosSupport];
    for (NSInteger row = 0; row < 3; row++) {
        for (NSInteger column = 0; column < 6; column++) {
            SCNNode *crystal = LHCBox(SCNVector3Make(0.17, 0.17, 0.18), 0.018,
                                      phos,
                                      SCNVector3Make(-1.01 + (CGFloat)column * 0.19,
                                                     1.94 + (CGFloat)row * 0.185,
                                                     -0.22 + (CGFloat)row * 0.22));
            [shell addChildNode:crystal];
        }
    }

    // Forward muon spectrometer with a conical absorber, dipole and tracking
    // stations built as open frames rather than solid slabs.
    SCNNode *absorber = LHCCone(0.46, 0.77, 0.72, bronze,
                                SCNVector3Make(0.39, LHCBeamHeight, 0), YES);
    [shell addChildNode:absorber];
    [shell addChildNode:LHCTorus(0.47, 0.035, polished,
                                 SCNVector3Make(0.74, LHCBeamHeight, 0), YES)];

    SCNNode *dipole = [SCNNode node];
    dipole.position = SCNVector3Make(0.97, LHCBeamHeight, 0);
    [shell addChildNode:dipole];
    [dipole addChildNode:LHCBox(SCNVector3Make(0.62, 0.24, 1.36), 0.035, blue,
                                SCNVector3Make(0, 0.72, 0))];
    [dipole addChildNode:LHCBox(SCNVector3Make(0.62, 0.24, 1.36), 0.035, blue,
                                SCNVector3Make(0, -0.56, 0))];
    for (NSInteger side = -1; side <= 1; side += 2) {
        [dipole addChildNode:LHCBox(SCNVector3Make(0.62, 0.98, 0.22), 0.028, blue,
                                    SCNVector3Make(0, 0.08, (CGFloat)side * 0.58))];
    }
    [dipole addChildNode:LHCTorus(0.48, 0.028, glow,
                                  SCNVector3Make(0, 0.10, 0), YES)];

    for (NSInteger i = 0; i < 3; i++) {
        CGFloat x = 1.40 + (CGFloat)i * 0.27;
        SCNNode *station = [SCNNode node];
        station.position = SCNVector3Make(x, LHCBeamHeight, 0);
        [shell addChildNode:station];
        for (NSInteger edge = -1; edge <= 1; edge += 2) {
            [station addChildNode:LHCBox(SCNVector3Make(0.055, 1.30, 0.075), 0.006,
                                         steel, SCNVector3Make(0, 0, (CGFloat)edge * 1.22))];
            [station addChildNode:LHCBox(SCNVector3Make(0.055, 0.075, 1.48), 0.006,
                                         steel, SCNVector3Make(0, (CGFloat)edge * 0.63, 0))];
        }
        [station addChildNode:LHCBox(SCNVector3Make(0.045, 1.16, 1.16), 0.006,
                                     silver, SCNVector3Zero)];
        SCNNode *line = LHCBox(SCNVector3Make(0.050, 0.024, 1.06), 0.003, glow,
                               SCNVector3Zero);
        line.castsShadow = NO;
        [station addChildNode:line];
    }

    [shell addChildNode:LHCBox(SCNVector3Make(0.22, 1.15, 1.32), 0.025, bronze,
                               SCNVector3Make(2.10, LHCBeamHeight + 0.01, 0))];
    SCNNode *triggerWall = LHCBox(SCNVector3Make(0.13, 1.52, 1.62), 0.024, green,
                                  SCNVector3Make(2.34, LHCBeamHeight, 0));
    [shell addChildNode:triggerWall];
    for (NSInteger i = 0; i < 4; i++) {
        SCNNode *slot = LHCBox(SCNVector3Make(0.15, 0.030, 1.38), 0.004, accentGlow,
                               SCNVector3Make(2.35, LHCBeamHeight - 0.50 + (CGFloat)i * 0.33, 0));
        slot.castsShadow = NO;
        [shell addChildNode:slot];
    }

    // Support cradle for the massive L3 barrel.
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *leg = LHCBox(SCNVector3Make(0.13, 0.58, 0.18), 0.012, steel,
                              SCNVector3Make(-0.42 + (CGFloat)side * 0.58, 0.60, 0));
        [root addChildNode:leg];
        SCNNode *foot = LHCBox(SCNVector3Make(0.42, 0.06, 0.52), 0.012, steel,
                               SCNVector3Make(-0.42 + (CGFloat)side * 0.58, 0.32, 0));
        [root addChildNode:foot];
    }
    SCNNode *forwardBeam = LHCBox(SCNVector3Make(2.0, 0.12, 0.20), 0.012, steel,
                                  SCNVector3Make(1.45, 0.48, 0));
    [root addChildNode:forwardBeam];

    return root;
}

#pragma mark LHCb

- (SCNNode *)buildLHCb {
    SCNNode *root = [SCNNode node];
    root.name = @"part.lhcb";
    NSColor *accent = LHCColor(0.33, 0.86, 0.58);
    [self addDetectorBaseToRoot:root width:5.25 depth:2.65 accent:accent];

    SCNMaterial *silver = LHCPBRMaterial(LHCColor(0.67, 0.72, 0.78), 0.23, 0.92);
    SCNMaterial *polished = LHCPBRMaterial(LHCColor(0.82, 0.85, 0.89), 0.16, 0.96);
    SCNMaterial *steel = LHCPBRMaterial(LHCColor(0.26, 0.31, 0.37), 0.30, 0.86);
    SCNMaterial *blue = LHCPanelMaterial(LHCColor(0.055, 0.26, 0.69),
                                         LHCColor(0.32, 0.70, 1.0), 0.25, 0.66);
    SCNMaterial *green = LHCPanelMaterial(LHCColor(0.10, 0.42, 0.21), accent, 0.32, 0.46);
    SCNMaterial *greenDeep = LHCPBRMaterial(LHCColor(0.06, 0.22, 0.12), 0.38, 0.42);
    SCNMaterial *yellow = LHCPanelMaterial(LHCColor(0.77, 0.64, 0.13),
                                            LHCColor(1.0, 0.89, 0.38), 0.28, 0.54);
    SCNMaterial *grey = LHCPBRMaterial(LHCColor(0.39, 0.43, 0.48), 0.36, 0.62);
    SCNMaterial *glass = LHCPBRMaterial(LHCColor(0.14, 0.20, 0.24), 0.12, 0.30);
    glass.transparency = 0.42;
    glass.blendMode = SCNBlendModeAlpha;
    SCNMaterial *glow = LHCEmissiveMaterial(LHCColor(0.30, 0.96, 0.65), 1.35);

    [root addChildNode:LHCCylinder(0.038, 5.35, polished,
                                   SCNVector3Make(0, LHCBeamHeight, 0), YES)];
    for (NSInteger i = -3; i <= 3; i++) {
        [root addChildNode:LHCCylinder(0.060, 0.028, silver,
                                       SCNVector3Make((CGFloat)i * 0.78,
                                                      LHCBeamHeight, 0), YES)];
    }

    // Vertex Locator: two retractable halves with individual silicon modules.
    SCNNode *velo = [SCNNode node];
    velo.position = SCNVector3Make(-2.26, LHCBeamHeight, 0);
    [root addChildNode:velo];
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *half = LHCBox(SCNVector3Make(0.46, 0.25, 0.055), 0.008, silver,
                               SCNVector3Make(0, 0, (CGFloat)side * 0.10));
        half.eulerAngles = SCNVector3Make((CGFloat)side * 0.22, 0, 0);
        [velo addChildNode:half];
        for (NSInteger i = 0; i < 3; i++) {
            SCNNode *module = LHCBox(SCNVector3Make(0.10, 0.23, 0.018), 0.003, glow,
                                     SCNVector3Make(-0.16 + (CGFloat)i * 0.16, 0,
                                                    (CGFloat)side * 0.13));
            module.castsShadow = NO;
            [velo addChildNode:module];
        }
    }
    [velo addChildNode:LHCTorus(0.22, 0.010, polished, SCNVector3Zero, YES)];

    SCNNode *shell = [self newOuterShellForRoot:root];

    // RICH-1: gas vessel, focusing mirror and photodetector plane.
    SCNNode *rich1 = [SCNNode node];
    rich1.position = SCNVector3Make(-1.72, LHCBeamHeight + 0.04, 0);
    [shell addChildNode:rich1];
    [rich1 addChildNode:LHCBox(SCNVector3Make(0.62, 1.18, 1.22), 0.07, grey,
                               SCNVector3Zero)];
    [rich1 addChildNode:LHCBox(SCNVector3Make(0.50, 0.84, 0.90), 0.025, glass,
                               SCNVector3Make(0.04, 0, 0))];
    for (NSInteger edge = -1; edge <= 1; edge += 2) {
        [rich1 addChildNode:LHCBox(SCNVector3Make(0.64, 0.055, 0.055), 0.007,
                                   polished,
                                   SCNVector3Make(0, (CGFloat)edge * 0.55, 0.56))];
        [rich1 addChildNode:LHCBox(SCNVector3Make(0.64, 1.08, 0.030), 0.004,
                                   steel,
                                   SCNVector3Make(0, 0, (CGFloat)edge * 0.60))];
    }
    [rich1 addChildNode:LHCCylinder(0.31, 0.035, polished,
                                    SCNVector3Make(-0.28, 0, 0), YES)];
    [rich1 addChildNode:LHCCylinder(0.09, 0.035, glow,
                                    SCNVector3Make(0.29, 0, 0), YES)];

    // Large dipole magnet: open blue yoke with a warm bore and coil package.
    SCNNode *magnet = [SCNNode node];
    magnet.position = SCNVector3Make(-0.88, LHCBeamHeight, 0);
    [shell addChildNode:magnet];
    [magnet addChildNode:LHCBox(SCNVector3Make(1.05, 0.34, 1.72), 0.035, blue,
                                SCNVector3Make(0, 0.83, 0))];
    [magnet addChildNode:LHCBox(SCNVector3Make(1.05, 0.34, 1.72), 0.035, blue,
                                SCNVector3Make(0, -0.62, 0))];
    for (NSInteger side = -1; side <= 1; side += 2) {
        [magnet addChildNode:LHCBox(SCNVector3Make(1.05, 1.20, 0.34), 0.032, blue,
                                    SCNVector3Make(0, 0.10, (CGFloat)side * 0.70))];
        [magnet addChildNode:LHCCylinder(0.15, 0.92, silver,
                                          SCNVector3Make(0, 0.32, (CGFloat)side * 0.49), YES)];
        [magnet addChildNode:LHCTorus(0.20, 0.024, glow,
                                       SCNVector3Make(0, 0.12, (CGFloat)side * 0.50), YES)];
    }
    [magnet addChildNode:LHCCylinder(0.06, 0.85, polished,
                                     SCNVector3Make(0, 0.12, 0), YES)];
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *cryo = LHCCylinder(0.027, 1.86, polished,
                                     SCNVector3Make(0, 0.99, (CGFloat)side * 0.34), YES);
        [magnet addChildNode:cryo];
    }
    SCNNode *magnetLabel = LHCBox(SCNVector3Make(0.22, 0.055, 1.42), 0.010, glow,
                                   SCNVector3Make(0.53, 0.22, 0));
    magnetLabel.castsShadow = NO;
    [magnet addChildNode:magnetLabel];

    // RICH-2 vessel with a segmented photodetector plane.
    SCNNode *rich2 = [SCNNode node];
    rich2.position = SCNVector3Make(-0.03, LHCBeamHeight + 0.02, 0);
    [shell addChildNode:rich2];
    [rich2 addChildNode:LHCBox(SCNVector3Make(0.70, 1.48, 1.56), 0.065, grey,
                                SCNVector3Zero)];
    [rich2 addChildNode:LHCBox(SCNVector3Make(0.56, 1.22, 1.28), 0.026, glass,
                                SCNVector3Make(0.03, 0, 0))];
    for (NSInteger i = 0; i < 4; i++) {
        [rich2 addChildNode:LHCBox(SCNVector3Make(0.075, 1.24, 0.23), 0.008, steel,
                                    SCNVector3Make(0.35, 0,
                                                   -0.54 + (CGFloat)i * 0.36))];
    }
    for (NSInteger edge = -1; edge <= 1; edge += 2) {
        [rich2 addChildNode:LHCTorus(0.39, 0.018, glow,
                                      SCNVector3Make(-0.18, 0, 0), YES)];
        [rich2 addChildNode:LHCBox(SCNVector3Make(0.72, 0.045, 0.045), 0.005, polished,
                                    SCNVector3Make(0, (CGFloat)edge * 0.72, 0.76))];
    }

    // Tracker station and silicon planes.
    SCNNode *tracker = [SCNNode node];
    tracker.position = SCNVector3Make(0.55, LHCBeamHeight, 0);
    [shell addChildNode:tracker];
    for (NSInteger edge = -1; edge <= 1; edge += 2) {
        [tracker addChildNode:LHCBox(SCNVector3Make(0.11, 1.36, 0.07), 0.006, steel,
                                      SCNVector3Make(0, 0, (CGFloat)edge * 1.31))];
        [tracker addChildNode:LHCBox(SCNVector3Make(0.11, 0.07, 1.54), 0.006, steel,
                                      SCNVector3Make(0, (CGFloat)edge * 0.67, 0))];
    }
    for (NSInteger layer = 0; layer < 3; layer++) {
        [tracker addChildNode:LHCBox(SCNVector3Make(0.035, 1.18, 1.18), 0.004, silver,
                                      SCNVector3Make(-0.10 + (CGFloat)layer * 0.10, 0, 0))];
        SCNNode *line = LHCBox(SCNVector3Make(0.045, 0.025, 1.06), 0.003, glow,
                               SCNVector3Make(-0.10 + (CGFloat)layer * 0.10, 0, 0));
        line.castsShadow = NO;
        [tracker addChildNode:line];
    }

    // Electromagnetic and hadronic calorimeters with sampling gaps.
    SCNNode *ecal = [SCNNode node];
    ecal.position = SCNVector3Make(0.91, LHCBeamHeight, 0);
    [shell addChildNode:ecal];
    [ecal addChildNode:LHCBox(SCNVector3Make(0.25, 1.52, 1.55), 0.020, yellow,
                              SCNVector3Zero)];
    for (NSInteger i = 0; i < 4; i++) {
        [ecal addChildNode:LHCBox(SCNVector3Make(0.27, 0.024, 1.34), 0.003, steel,
                                  SCNVector3Make(0, -0.51 + (CGFloat)i * 0.34, 0))];
    }
    SCNNode *hcal = [SCNNode node];
    hcal.position = SCNVector3Make(1.24, LHCBeamHeight, 0);
    [shell addChildNode:hcal];
    [hcal addChildNode:LHCBox(SCNVector3Make(0.38, 1.72, 1.70), 0.024, green,
                              SCNVector3Zero)];
    for (NSInteger i = 0; i < 4; i++) {
        [hcal addChildNode:LHCBox(SCNVector3Make(0.40, 0.022, 1.52), 0.003, greenDeep,
                                  SCNVector3Make(0, -0.54 + (CGFloat)i * 0.36, 0))];
    }

    // Muon stations grow progressively outward toward the trigger wall.
    // Each station is an open grid of individual chambers, not a solid slab,
    // so the forward spectrometer remains readable from oblique angles.
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat x = 1.64 + (CGFloat)i * 0.30;
        CGFloat height = 1.28 + (CGFloat)i * 0.20;
        CGFloat width = 1.42 + (CGFloat)i * 0.22;
        SCNNode *station = [SCNNode node];
        station.position = SCNVector3Make(x, LHCBeamHeight, 0);
        [shell addChildNode:station];

        // Outer support frame.
        for (NSInteger edge = -1; edge <= 1; edge += 2) {
            [station addChildNode:LHCBox(SCNVector3Make(0.10, height, 0.07), 0.005,
                                         silver, SCNVector3Make(0, 0, (CGFloat)edge * width * 0.5))];
            [station addChildNode:LHCBox(SCNVector3Make(0.10, 0.07, width), 0.005,
                                         silver, SCNVector3Make(0, (CGFloat)edge * height * 0.5, 0))];
            // Corner gussets make the frame read as a fabricated structure.
            [station addChildNode:LHCBox(SCNVector3Make(0.11, 0.22, 0.22), 0.006,
                                         steel, SCNVector3Make(0, (CGFloat)edge * (height * 0.5 - 0.11),
                                                               (CGFloat)edge * (width * 0.5 - 0.11)))];
        }

        NSInteger rows = (i == 3) ? 4 : 3;
        NSInteger columns = (i == 3) ? 4 : 3;
        CGFloat gridHeight = height * 0.88;
        CGFloat gridWidth = width * 0.88;
        CGFloat cellHeight = gridHeight / (CGFloat)rows;
        CGFloat cellWidth = gridWidth / (CGFloat)columns;
        for (NSInteger row = 0; row < rows; row++) {
            for (NSInteger column = 0; column < columns; column++) {
                // Leave a beam aperture in the centre of each station.
                if (row == rows / 2 && column == columns / 2) {
                    continue;
                }
                CGFloat y = -gridHeight * 0.5 + cellHeight * ((CGFloat)row + 0.5);
                CGFloat z = -gridWidth * 0.5 + cellWidth * ((CGFloat)column + 0.5);
                SCNNode *chamber = LHCBox(SCNVector3Make(0.045, cellHeight * 0.84,
                                                          cellWidth * 0.84),
                                           0.004, grey, SCNVector3Make(0, y, z));
                [station addChildNode:chamber];

                SCNNode *readout = LHCBox(SCNVector3Make(0.050, cellHeight * 0.075,
                                                          cellWidth * 0.74),
                                          0.002, glow, SCNVector3Make(0, y, z));
                readout.castsShadow = NO;
                [station addChildNode:readout];
            }
        }

        // Chamber-grid dividers.
        for (NSInteger row = 1; row < rows; row++) {
            CGFloat y = -gridHeight * 0.5 + cellHeight * (CGFloat)row;
            [station addChildNode:LHCBox(SCNVector3Make(0.060, 0.026, gridWidth), 0.003,
                                         steel, SCNVector3Make(0, y, 0))];
        }
        for (NSInteger column = 1; column < columns; column++) {
            CGFloat z = -gridWidth * 0.5 + cellWidth * (CGFloat)column;
            [station addChildNode:LHCBox(SCNVector3Make(0.060, gridHeight, 0.026), 0.003,
                                         steel, SCNVector3Make(0, 0, z))];
        }

        // A bright aperture ring around the beam pipe.
        [station addChildNode:LHCTorus(0.22, 0.016, glow, SCNVector3Zero, YES)];
    }

    // Support rails and a cable tray under the forward spectrometer.
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNNode *leg = LHCBox(SCNVector3Make(0.12, 0.50, 0.16), 0.012, steel,
                              SCNVector3Make(0.92, 0.56, (CGFloat)side * 0.80));
        [root addChildNode:leg];
        SCNNode *foot = LHCBox(SCNVector3Make(0.34, 0.05, 0.40), 0.010, steel,
                               SCNVector3Make(0.92, 0.325, (CGFloat)side * 0.80));
        [root addChildNode:foot];
    }
    SCNNode *serviceTray = LHCBox(SCNVector3Make(3.7, 0.055, 0.16), 0.010, steel,
                                  SCNVector3Make(0.65, 0.31, 0));
    [root addChildNode:serviceTray];

    return root;
}

#pragma mark Detectors assembly

- (void)buildDetectors {
    SCNNode *detectors = [SCNNode node];
    [self.scene.rootNode addChildNode:detectors];
    self.detectorsNode = detectors;

    NSArray<NSDictionary *> *definitions = @[
        @{@"identifier": @"atlas", @"name": @"ATLAS", @"angle": @225.0,
          @"accent": LHCColor(0.35, 0.66, 1.0), @"labelHeight": @3.10},
        @{@"identifier": @"cms", @"name": @"CMS", @"angle": @315.0,
          @"accent": LHCColor(0.94, 0.27, 0.30), @"labelHeight": @3.05},
        @{@"identifier": @"alice", @"name": @"ALICE", @"angle": @135.0,
          @"accent": LHCColor(0.96, 0.74, 0.23), @"labelHeight": @2.95},
        @{@"identifier": @"lhcb", @"name": @"LHCb", @"angle": @45.0,
          @"accent": LHCColor(0.33, 0.86, 0.58), @"labelHeight": @2.85}
    ];

    for (NSDictionary *definition in definitions) {
        NSString *identifier = definition[@"identifier"];
        SCNNode *root;
        if ([identifier isEqualToString:@"atlas"]) {
            root = [self buildATLAS];
        } else if ([identifier isEqualToString:@"cms"]) {
            root = [self buildCMS];
        } else if ([identifier isEqualToString:@"alice"]) {
            root = [self buildALICE];
        } else {
            root = [self buildLHCb];
        }

        CGFloat angle = [definition[@"angle"] doubleValue] * (CGFloat)M_PI / 180.0;
        root.position = SCNVector3Make(cosf(angle) * LHCRingRadius, 0, sinf(angle) * LHCRingRadius);
        root.eulerAngles = SCNVector3Make(0, -angle, 0);
        // Horizontal footprint is configurable; height stays locked to the beamline.
        root.scale = SCNVector3Make(self.configuration.detectorScale,
                                    1.0,
                                    self.configuration.detectorScale);
        [detectors addChildNode:root];
        self.detectorNodes[identifier] = root;

        [self addDetectorLabelForIdentifier:identifier
                                       name:definition[@"name"]
                                     accent:definition[@"accent"]
                                     height:[definition[@"labelHeight"] doubleValue]
                               worldPosition:root.position];
    }
}

- (void)buildProtonBunches {
    NSMutableArray<SCNNode *> *tracersA = [NSMutableArray array];
    NSMutableArray<SCNNode *> *tracersB = [NSMutableArray array];

    self.beamGroupA = [self beamGroupWithColor:LHCColor(0.31, 0.92, 1.0)
                                    radialOffset:LHCBeamARadialOffset
                                            name:@"part.beam"
                                  trailDirection:1.0
                                   tracerStorage:tracersA];
    self.beamGroupB = [self beamGroupWithColor:LHCColor(1.0, 0.32, 0.82)
                                    radialOffset:LHCBeamBRadialOffset
                                            name:@"part.beam"
                                  trailDirection:-1.0
                                   tracerStorage:tracersB];
    self.beamTracerRootsA = [tracersA copy];
    self.beamTracerRootsB = [tracersB copy];
    [self.scene.rootNode addChildNode:self.beamGroupA];
    [self.scene.rootNode addChildNode:self.beamGroupB];
}

- (SCNNode *)beamGroupWithColor:(NSColor *)color
                   radialOffset:(CGFloat)radialOffset
                           name:(NSString *)name
                 trailDirection:(CGFloat)trailDirection
                  tracerStorage:(NSMutableArray<SCNNode *> *)tracerStorage {
    SCNNode *group = [SCNNode node];
    group.name = name;
    group.position = SCNVector3Make(0, LHCBeamHeight, 0);

    SCNMaterial *protonMaterial = [SCNMaterial material];
    protonMaterial.lightingModelName = SCNLightingModelConstant;
    protonMaterial.diffuse.contents = color;
    protonMaterial.emission.contents = color;
    protonMaterial.emission.intensity = 2.0;
    protonMaterial.writesToDepthBuffer = NO;

    SCNSphere *sphere = [SCNSphere sphereWithRadius:0.030];
    sphere.segmentCount = 12;
    sphere.materials = @[protonMaterial];

    const NSInteger bunchCount = 40;
    const CGFloat orbitRadius = LHCRingRadius + radialOffset;
    for (NSInteger i = 0; i < bunchCount; i++) {
        CGFloat angle = (CGFloat)i / (CGFloat)bunchCount * M_PI * 2.0;
        SCNNode *bunch = [SCNNode node];
        bunch.position = SCNVector3Make(cosf(angle) * orbitRadius, 0, sinf(angle) * orbitRadius);
        bunch.eulerAngles = SCNVector3Make(0, -angle, 0);

        for (NSInteger j = -1; j <= 1; j++) {
            SCNNode *proton = [SCNNode nodeWithGeometry:sphere];
            proton.position = SCNVector3Make((CGFloat)j * 0.044, 0, 0);
            proton.castsShadow = NO;
            [bunch addChildNode:proton];
        }
        SCNNode *core = [SCNNode nodeWithGeometry:sphere];
        core.scale = SCNVector3Make(0.52, 0.52, 0.52);
        core.position = SCNVector3Make(0, 0, 0);
        core.castsShadow = NO;
        [bunch addChildNode:core];

        [group addChildNode:bunch];
    }

    // The evenly spaced bunch train is almost rotationally symmetric. Build a
    // pool of bright tracers with comet tails so the counter-rotation is
    // legible; applyBeamParticleCount: chooses how many are visible.
    NSColor *hotColor = [color blendedColorWithFraction:0.88
                                                ofColor:[NSColor whiteColor]] ?: color;
    SCNMaterial *tracerMaterial = [protonMaterial copy];
    tracerMaterial.diffuse.contents = hotColor;
    tracerMaterial.emission.contents = hotColor;
    tracerMaterial.emission.intensity = 4.6;
    tracerMaterial.readsFromDepthBuffer = NO;
    SCNSphere *tracerSphere = [SCNSphere sphereWithRadius:0.085];
    tracerSphere.segmentCount = 24;
    tracerSphere.materials = @[tracerMaterial];

    SCNMaterial *innerHaloMaterial = [SCNMaterial material];
    innerHaloMaterial.lightingModelName = SCNLightingModelConstant;
    innerHaloMaterial.diffuse.contents = [color colorWithAlphaComponent:0.18];
    innerHaloMaterial.emission.contents = color;
    innerHaloMaterial.emission.intensity = 2.4;
    innerHaloMaterial.blendMode = SCNBlendModeAdd;
    innerHaloMaterial.writesToDepthBuffer = NO;
    innerHaloMaterial.readsFromDepthBuffer = NO;
    SCNSphere *innerHaloSphere = [SCNSphere sphereWithRadius:0.19];
    innerHaloSphere.segmentCount = 24;
    innerHaloSphere.materials = @[innerHaloMaterial];

    SCNMaterial *outerHaloMaterial = [SCNMaterial material];
    outerHaloMaterial.lightingModelName = SCNLightingModelConstant;
    outerHaloMaterial.diffuse.contents = [color colorWithAlphaComponent:0.07];
    outerHaloMaterial.emission.contents = color;
    outerHaloMaterial.emission.intensity = 1.3;
    outerHaloMaterial.blendMode = SCNBlendModeAdd;
    outerHaloMaterial.writesToDepthBuffer = NO;
    outerHaloMaterial.readsFromDepthBuffer = NO;
    SCNSphere *outerHaloSphere = [SCNSphere sphereWithRadius:0.36];
    outerHaloSphere.segmentCount = 24;
    outerHaloSphere.materials = @[outerHaloMaterial];

    SCNMaterial *trailMaterial = [protonMaterial copy];
    trailMaterial.emission.intensity = 1.9;
    trailMaterial.readsFromDepthBuffer = NO;
    SCNSphere *trailSphere = [SCNSphere sphereWithRadius:0.032];
    trailSphere.segmentCount = 12;
    trailSphere.materials = @[trailMaterial];

    for (NSInteger tracerIndex = 0; tracerIndex < LHCBeamTracerMaximum; tracerIndex++) {
        SCNNode *tracer = [SCNNode node];
        tracer.name = @"beam.tracer";
        tracer.hidden = YES;
        [group addChildNode:tracer];
        [tracerStorage addObject:tracer];

        SCNNode *tracerCore = [SCNNode nodeWithGeometry:tracerSphere];
        tracerCore.castsShadow = NO;
        [tracer addChildNode:tracerCore];

        SCNNode *innerHalo = [SCNNode nodeWithGeometry:innerHaloSphere];
        innerHalo.castsShadow = NO;
        [tracer addChildNode:innerHalo];

        SCNNode *outerHalo = [SCNNode nodeWithGeometry:outerHaloSphere];
        outerHalo.castsShadow = NO;
        [tracer addChildNode:outerHalo];

        SCNAction *innerUp = [SCNAction scaleTo:1.16 duration:0.72];
        innerUp.timingMode = SCNActionTimingModeEaseInEaseOut;
        SCNAction *innerDown = [SCNAction scaleTo:0.88 duration:0.72];
        innerDown.timingMode = SCNActionTimingModeEaseInEaseOut;
        [innerHalo runAction:[SCNAction repeatActionForever:
            [SCNAction sequence:@[innerUp, innerDown]]]];

        SCNAction *outerDown = [SCNAction scaleTo:0.88 duration:0.72];
        outerDown.timingMode = SCNActionTimingModeEaseInEaseOut;
        SCNAction *outerUp = [SCNAction scaleTo:1.16 duration:0.72];
        outerUp.timingMode = SCNActionTimingModeEaseInEaseOut;
        [outerHalo runAction:[SCNAction repeatActionForever:
            [SCNAction sequence:@[outerDown, outerUp]]]];

        for (NSInteger i = 1; i <= 10; i++) {
            CGFloat distance = (CGFloat)i * 0.009 * orbitRadius;
            SCNNode *dot = [SCNNode nodeWithGeometry:trailSphere];
            dot.position = SCNVector3Make(0, 0, trailDirection * distance);
            dot.opacity = 0.62 * (1.0 - (CGFloat)i / 12.0);
            CGFloat scale = 1.0 - (CGFloat)i * 0.055;
            dot.scale = SCNVector3Make(scale, scale, scale);
            dot.castsShadow = NO;
            [tracer addChildNode:dot];
        }
    }

    return group;
}

- (void)applyBeamParticleCount:(NSInteger)count {
    if (self.beamTracerRootsA.count == 0 || self.beamTracerRootsB.count == 0) {
        return;
    }
    NSInteger clamped = MIN(MAX(count, 1), LHCBeamTracerMaximum);
    [self layoutBeamTracers:self.beamTracerRootsA
                      count:clamped
                     radius:LHCRingRadius + LHCBeamARadialOffset];
    [self layoutBeamTracers:self.beamTracerRootsB
                      count:clamped
                     radius:LHCRingRadius + LHCBeamBRadialOffset];
}

- (void)layoutBeamTracers:(NSArray<SCNNode *> *)tracers
                    count:(NSInteger)count
                   radius:(CGFloat)radius {
    for (NSInteger i = 0; i < (NSInteger)tracers.count; i++) {
        SCNNode *tracer = tracers[i];
        if (i >= count) {
            tracer.hidden = YES;
            continue;
        }

        tracer.hidden = NO;
        CGFloat angle = (CGFloat)i / (CGFloat)count * (CGFloat)M_PI * 2.0;
        tracer.position = SCNVector3Make(cosf(angle) * radius, 0,
                                         sinf(angle) * radius);
        tracer.eulerAngles = SCNVector3Make(0, -angle, 0);
    }
}

#pragma mark Selection indicator

- (void)buildSelectionIndicator {
    SCNNode *selection = [SCNNode node];
    selection.name = @"selection.indicator";
    selection.hidden = YES;
    [self.scene.rootNode addChildNode:selection];
    self.selectionNode = selection;

    SCNMaterial *ringMaterial = LHCEmissiveMaterial(LHCColor(0.40, 0.92, 1.0), 2.0);
    ringMaterial.transparency = 0.9;
    self.selectionRingMaterial = ringMaterial;
    SCNNode *ring = LHCTorus(1.0, 0.018, ringMaterial, SCNVector3Make(0, 0.02, 0), NO);
    ring.castsShadow = NO;
    ring.name = @"selection.ring";
    [selection addChildNode:ring];
    self.selectionRingNode = ring;

    // Slow pulse makes the selection feel alive without distracting from the model.
    SCNAction *grow = [SCNAction scaleTo:1.045 duration:0.95];
    grow.timingMode = SCNActionTimingModeEaseInEaseOut;
    SCNAction *shrink = [SCNAction scaleTo:1.0 duration:0.95];
    shrink.timingMode = SCNActionTimingModeEaseInEaseOut;
    [ring runAction:[SCNAction repeatActionForever:[SCNAction sequence:@[grow, shrink]]]];

}

#pragma mark Part catalog

- (void)registerPart:(LHCPartInfo *)part {
    self.mutableCatalog[part.identifier] = part;
}

- (void)buildPartCatalog {
    NSColor *overviewAccent = LHCColor(0.43, 0.82, 1.0);
    NSColor *blue = LHCColor(0.35, 0.66, 1.0);
    NSColor *red = LHCColor(0.95, 0.32, 0.34);
    NSColor *amber = LHCColor(0.96, 0.74, 0.23);
    NSColor *green = LHCColor(0.33, 0.86, 0.58);

    [self registerPart:[[LHCPartInfo alloc]
        initWithIdentifier:@"overview"
                      name:@"Large Hadron Collider"
                  category:@"CERN · 27 km accelerator"
                   summary:@"The LHC is the world’s largest and most powerful particle accelerator: a ring of superconducting magnets beneath the French–Swiss border. Two beams of protons circulate in opposite directions and are focused into collisions at four interaction points."
                     facts:@[@"Circumference — 26.7 km",
                             @"Beam energy — up to 6.8 TeV",
                             @"Operating temperature — 1.9 K",
                             @"First collisions — 2009"]
               accentColor:overviewAccent
                  detector:NO]];

    [self registerPart:[[LHCPartInfo alloc]
        initWithIdentifier:@"vacuum"
                      name:@"Beam vacuum & tunnel"
                  category:@"Accelerator infrastructure"
                   summary:@"Each proton beam travels through a steel pipe held at ultra-high vacuum, comparable to interplanetary space, so protons do not scatter from residual gas. The twin pipes share a common cryostat inside the 27 km tunnel."
                     facts:@[@"Tunnel depth — 50–175 m",
                             @"Beam pipe pressure — ~10⁻¹⁰ mbar",
                             @"Two counter-rotating beam pipes",
                             @"Magnets cooled by superfluid helium"]
               accentColor:LHCColor(0.48, 0.74, 0.88)
                  detector:NO]];

    [self registerPart:[[LHCPartInfo alloc]
        initWithIdentifier:@"dipole"
                      name:@"Dipole bending magnets"
                  category:@"Magnet lattice · blue"
                   summary:@"Superconducting dipole magnets steer the beams around the ring. Their niobium–titanium coils operate at −271.25 °C, below the temperature of outer space, allowing huge currents and magnetic fields."
                     facts:@[@"1,232 dipole magnets",
                             @"Length — 15 m each",
                             @"Mass — 35 t each",
                             @"Field — up to 8.33 T"]
               accentColor:blue
                  detector:NO]];

    [self registerPart:[[LHCPartInfo alloc]
        initWithIdentifier:@"quadrupole"
                      name:@"Quadrupole focusing magnets"
                  category:@"Magnet lattice · red"
                   summary:@"Quadrupoles squeeze the beam and focus it into tightly packed proton bunches. In the final focus before a detector, special insertion magnets compress the beam to the width of a human hair."
                     facts:@[@"392 quadrupole magnets",
                             @"Length — 3–4 m each",
                             @"Final beam size — ~64 µm",
                             @"Keeps bunches tightly focused"]
               accentColor:red
                  detector:NO]];

    [self registerPart:[[LHCPartInfo alloc]
        initWithIdentifier:@"rf"
                      name:@"RF accelerating cavities"
                  category:@"Acceleration"
                   summary:@"Radio-frequency cavities give the proton bunches an energy kick on every lap. The LHC uses eight superconducting cavities per beam, resonating at 400 MHz."
                     facts:@[@"RF frequency — 400 MHz",
                             @"8 cavities per beam",
                             @"Energy gain — 16 MV per beam",
                             @"Bunches kept in stable buckets"]
               accentColor:LHCColor(0.30, 0.94, 0.88)
                  detector:NO]];

    [self registerPart:[[LHCPartInfo alloc]
        initWithIdentifier:@"beam"
                      name:@"Counter-rotating proton beams"
                  category:@"Beam simulation"
                   summary:@"Two beams of proton bunches travel in opposite directions around the ring. A bunch contains around 100 billion protons, and bunches are spaced 25 nanoseconds apart. The glowing trails in this model are stylised."
                     facts:@[@"2,808 bunches per beam",
                             @"~1.15 × 10¹¹ protons per bunch",
                             @"Bunch spacing — 25 ns",
                             @"Collision rate — up to 40 MHz"]
               accentColor:LHCColor(0.40, 0.92, 1.0)
                  detector:NO]];

    [self registerPart:[[LHCPartInfo alloc]
        initWithIdentifier:@"atlas"
                      name:@"ATLAS"
                  category:@"General-purpose detector"
                   summary:@"ATLAS (A Toroidal LHC ApparatuS) is the largest detector at the LHC. Three giant toroid magnets and a central solenoid curve charged-particle tracks, while layered tracking and calorimetry record their energy and momentum. ATLAS co-discovered the Higgs boson in 2012."
                     facts:@[@"Length — 46 m",
                             @"Height — 25 m",
                             @"Mass — about 7,000 t",
                             @"Three toroid magnets + solenoid"]
               accentColor:blue
                  detector:YES]];

    [self registerPart:[[LHCPartInfo alloc]
        initWithIdentifier:@"cms"
                      name:@"CMS"
                  category:@"General-purpose detector"
                   summary:@"CMS (Compact Muon Solenoid) is built around a huge superconducting solenoid whose field is more than 100,000 times stronger than Earth’s. Its compact, layered design measures electrons, photons, hadrons and muons produced in high-energy collisions."
                     facts:@[@"Length — 21.6 m",
                             @"Diameter — 15 m",
                             @"Mass — about 14,000 t",
                             @"Solenoid field — 3.8 T"]
               accentColor:red
                  detector:YES]];

    [self registerPart:[[LHCPartInfo alloc]
        initWithIdentifier:@"alice"
                      name:@"ALICE"
                  category:@"Heavy-ion detector"
                   summary:@"ALICE studies the quark–gluon plasma created when lead nuclei collide. Its central tracking system, time projection chamber and forward muon spectrometer reveal how matter behaved a fraction of a second after the Big Bang."
                     facts:@[@"Length — 26 m",
                             @"Height — 16 m",
                             @"Mass — about 10,000 t",
                             @"Optimised for lead–lead collisions"]
               accentColor:amber
                  detector:YES]];

    [self registerPart:[[LHCPartInfo alloc]
        initWithIdentifier:@"lhcb"
                      name:@"LHCb"
                  category:@"Forward beauty-physics detector"
                   summary:@"LHCb is a forward spectrometer built to study particles containing beauty quarks. Precise tracking, RICH detectors and calorimeters investigate why the Universe contains far more matter than antimatter."
                     facts:@[@"Length — 21 m",
                             @"Mass — about 5,600 t",
                             @"Forward angular coverage",
                             @"RICH detectors identify particle types"]
               accentColor:green
                  detector:YES]];

    self.partCatalog = [self.mutableCatalog copy];
}

#pragma mark Configuration

- (void)applyModelConfiguration:(LHCSimulationConfig *)configuration {
    self.terrainNode.hidden = !configuration.showTerrain;
    self.tunnelNode.hidden = !configuration.showTunnel;
    self.magnetsNode.hidden = !configuration.showMagnets;
    self.detectorsNode.hidden = !configuration.showDetectors;

    self.labelsRoot.hidden = !configuration.showLabels || !configuration.showDetectors;
    for (SCNNode *shell in self.outerShells) {
        shell.opacity = configuration.cutawayView ? 0.16 : 1.0;
    }
    self.tunnelMaterial.transparency = configuration.tunnelOpacity;

    for (NSString *identifier in self.detectorIdentifiers) {
        SCNNode *detector = self.detectorNodes[identifier];
        CGFloat scale = configuration.detectorScale;
        detector.scale = SCNVector3Make(scale, 1.0, scale);
    }

    if (!configuration.showDetectors) {
        self.selectionNode.hidden = YES;
    }

    [self applyBeamParticleCount:configuration.beamParticleCount];
}

#pragma mark Hit testing

- (nullable SCNNode *)partNodeForHitNode:(SCNNode *)node {
    SCNNode *candidate = node;
    while (candidate) {
        NSString *name = candidate.name;
        if ([name hasPrefix:@"part."]) {
            NSString *identifier = [name substringFromIndex:5];
            if (self.partCatalog[identifier]) {
                return candidate;
            }
        }
        candidate = candidate.parentNode;
    }
    return nil;
}

- (nullable LHCPartInfo *)partInfoForHitNode:(SCNNode *)node {
    SCNNode *partNode = [self partNodeForHitNode:node];
    if (!partNode) {
        return nil;
    }
    return self.partCatalog[[partNode.name substringFromIndex:5]];
}

#pragma mark Detectors & collision geometry

- (SCNNode *)detectorNodeWithIdentifier:(NSString *)identifier {
    return self.detectorNodes[identifier];
}

- (SCNVector3)collisionPointForDetectorIdentifier:(NSString *)identifier {
    SCNNode *detector = self.detectorNodes[identifier];
    if (!detector) {
        return SCNVector3Make(0, LHCBeamHeight, 0);
    }
    return SCNVector3Make(detector.position.x, LHCBeamHeight, detector.position.z);
}

- (SCNVector3)beamTangentForDetectorIdentifier:(NSString *)identifier {
    SCNNode *detector = self.detectorNodes[identifier];
    if (!detector) {
        return SCNVector3Make(0, 0, 1);
    }
    SCNVector3 tangent = [detector convertVector:SCNVector3Make(1, 0, 0) toNode:nil];
    CGFloat length = sqrt(tangent.x * tangent.x + tangent.z * tangent.z);
    if (length < 0.0001) {
        return SCNVector3Make(0, 0, 1);
    }
    return SCNVector3Make(tangent.x / length, 0, tangent.z / length);
}

#pragma mark Highlight

- (void)highlightPartWithIdentifier:(nullable NSString *)identifier
                        accentColor:(nullable NSColor *)accentColor {
    LHCPartInfo *info = identifier ? self.partCatalog[identifier] : nil;
    SCNNode *node = identifier ? self.detectorNodes[identifier] : nil;
    if (!node && identifier) {
        // Find a representative lattice node for magnets / RF components.
        for (SCNNode *child in self.magnetsNode.childNodes) {
            if ([child.name isEqualToString:[@"part." stringByAppendingString:identifier]]) {
                node = child;
                break;
            }
        }
    }
    [self highlightNode:node partInfo:info accentColor:accentColor];
}

- (void)highlightNode:(nullable SCNNode *)partNode
           accentColor:(nullable NSColor *)accentColor {
    LHCPartInfo *info = partNode ? [self partInfoForHitNode:partNode] : nil;
    [self highlightNode:partNode partInfo:info accentColor:accentColor];
}

- (void)highlightNode:(nullable SCNNode *)node
             partInfo:(nullable LHCPartInfo *)info
          accentColor:(nullable NSColor *)accentColor {
    if (!node || !info) {
        self.selectionNode.hidden = YES;
        return;
    }

    NSString *identifier = info.identifier;
    if ([identifier isEqualToString:@"overview"] ||
        [identifier isEqualToString:@"vacuum"] ||
        [identifier isEqualToString:@"beam"]) {
        self.selectionNode.hidden = YES;
        return;
    }

    NSColor *color = accentColor ?: (info.accentColor ?: LHCColor(0.40, 0.92, 1.0));
    SCNMaterial *ringMaterial = self.selectionRingMaterial;
    ringMaterial.diffuse.contents = [color colorWithAlphaComponent:0.2];
    ringMaterial.emission.contents = color;

    SCNVector3 world = [node convertPosition:SCNVector3Make(0, 0, 0) toNode:nil];
    CGFloat scale = info.isDetector ? 1.75 : 0.62;
    self.selectionNode.position = SCNVector3Make(world.x, 0.045, world.z);
    self.selectionNode.scale = SCNVector3Make(scale, 1.0, scale);
    self.selectionNode.hidden = NO;
    self.selectionNode.opacity = 1.0;
}

#pragma mark Beam animation

- (void)advanceBeamsByRadians:(CGFloat)radians {
    self.beamPhase = fmodf(self.beamPhase + radians, (CGFloat)(M_PI * 2.0));
    self.beamGroupA.eulerAngles = SCNVector3Make(0, self.beamPhase, 0);
    self.beamGroupB.eulerAngles = SCNVector3Make(0, -self.beamPhase, 0);
}

- (void)resetBeamPhase {
    self.beamPhase = 0;
    self.beamGroupA.eulerAngles = SCNVector3Make(0, 0, 0);
    self.beamGroupB.eulerAngles = SCNVector3Make(0, 0, 0);
}

- (void)setBeamOpacity:(CGFloat)opacity {
    self.beamGroupA.opacity = opacity;
    self.beamGroupB.opacity = opacity;
}

@end
