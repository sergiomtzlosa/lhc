//
//  LHCViewController.m
//  LHC Interactive
//

#import "LHCViewController.h"
#import "LHCHadronModel.h"
#import "LHCParticleSystemFactory.h"
#import "LHCSceneView.h"
#import "LHCSimulationConfig.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Local view helpers

/// A visual-effect panel that passes clicks through to the 3D scene.
@interface LHCPassThroughEffectView : NSVisualEffectView
@end

@implementation LHCPassThroughEffectView
- (NSView *)hitTest:(NSPoint)point {
    return nil;
}
@end

/// A non-interactive view used for the brief collision screen flash. A radial
/// gradient keeps the centre bright without washing out the whole inspector.
@interface LHCMouseTransparentView : NSView
@property (nonatomic, strong) CAGradientLayer *flashGradient;
@end

@implementation LHCMouseTransparentView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor clearColor].CGColor;
        _flashGradient = [CAGradientLayer layer];
        _flashGradient.type = kCAGradientLayerRadial;
        _flashGradient.startPoint = CGPointMake(0.5, 0.5);
        _flashGradient.endPoint = CGPointMake(1.0, 1.0);
        _flashGradient.locations = @[@0.0, @0.34, @1.0];
        _flashGradient.colors = @[
            (id)[NSColor colorWithSRGBRed:0.82 green:0.97 blue:1.0 alpha:0.95].CGColor,
            (id)[NSColor colorWithSRGBRed:0.33 green:0.76 blue:1.0 alpha:0.30].CGColor,
            (id)[NSColor colorWithSRGBRed:0.05 green:0.22 blue:0.36 alpha:0.0].CGColor
        ];
        [self.layer addSublayer:_flashGradient];
    }
    return self;
}

- (void)layout {
    [super layout];
    self.flashGradient.frame = self.bounds;
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}
@end

/// The scroll document must be flipped so content begins at the top.
@interface LHCFlippedView : NSView
@end

@implementation LHCFlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

/// Rounded, appearance-aware panel used by cards in the inspector.
@interface LHCPanelView : NSView
@property (nonatomic, strong, nullable) NSColor *accentColor;
@end

@implementation LHCPanelView

- (void)setAccentColor:(NSColor *)accentColor {
    _accentColor = accentColor;
    [self setNeedsDisplay:YES];
}

- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSAppearance *appearance = self.effectiveAppearance;
    BOOL dark = [appearance.name isEqualToString:NSAppearanceNameDarkAqua];

    NSColor *fill = dark
        ? [NSColor colorWithCalibratedWhite:1.0 alpha:0.055]
        : [NSColor colorWithCalibratedWhite:1.0 alpha:0.52];
    NSColor *border = dark
        ? [NSColor colorWithCalibratedWhite:1.0 alpha:0.10]
        : [NSColor colorWithCalibratedWhite:0.0 alpha:0.075];

    NSRect rect = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:11 yRadius:11];
    [fill setFill];
    [path fill];
    [border setStroke];
    path.lineWidth = 1.0;
    [path stroke];

    if (self.accentColor) {
        NSRect barRect = NSMakeRect(1.5, 12, 3.0, MAX(0, NSHeight(self.bounds) - 24));
        NSBezierPath *bar = [NSBezierPath bezierPathWithRoundedRect:barRect xRadius:1.5 yRadius:1.5];
        [[self.accentColor colorWithAlphaComponent:0.9] setFill];
        [bar fill];
    }
}

@end

static NSImage *LHCSystemSymbol(NSString *name, CGFloat pointSize);

/// Push button with a coloured bezel and a title that remains legible when disabled.
@interface LHCProminentButton : NSButton
@property (nonatomic, copy, nullable) NSString *prominentTitle;
@property (nonatomic, copy, nullable) NSString *prominentSymbolName;
@property (nonatomic, strong, nullable) NSColor *prominentColor;
- (void)applyProminentTitle:(NSString *)title
                     symbol:(nullable NSString *)symbol
                      color:(nullable NSColor *)color;
@end

@implementation LHCProminentButton

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self renderProminentStyle];
}

- (void)applyProminentTitle:(NSString *)title
                     symbol:(nullable NSString *)symbol
                      color:(nullable NSColor *)color {
    self.prominentTitle = title;
    if (symbol.length > 0) {
        self.prominentSymbolName = symbol;
    }
    self.prominentColor = color;
    [self renderProminentStyle];
}

- (void)renderProminentStyle {
    NSString *title = self.prominentTitle ?: self.title;
    NSColor *color = self.prominentColor ?: [NSColor controlAccentColor];
    NSColor *titleColor = self.enabled ? [NSColor whiteColor] : [NSColor disabledControlTextColor];

    // AppKit draws a tinted push button with a light title regardless of the
    // attributed title colour. Dropping the bezel tint while disabled lets the
    // standard disabled appearance keep the label readable.
    self.bezelColor = self.enabled ? color : nil;
    self.contentTintColor = self.enabled ? titleColor : nil;
    if (self.prominentSymbolName.length > 0) {
        self.image = LHCSystemSymbol(self.prominentSymbolName, 12.0);
        self.imagePosition = NSImageLeading;
    }

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    self.attributedTitle = [[NSAttributedString alloc]
        initWithString:title
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold],
                NSForegroundColorAttributeName: titleColor,
                NSParagraphStyleAttributeName: paragraph
            }];
}

@end

/// Compact labelled slider used throughout the inspector.
@interface LHCSliderRowView : NSView
@property (nonatomic, strong, readonly) NSSlider *slider;
@property (nonatomic, strong, readonly) NSTextField *valueLabel;
@property (nonatomic, copy, nullable) NSString * (^valueFormatter)(double value);
- (instancetype)initWithTitle:(NSString *)title
                     minValue:(double)minValue
                     maxValue:(double)maxValue
                        value:(double)value
                     formatter:(nullable NSString * (^)(double value))formatter;
- (void)refreshValueLabel;
@end

@implementation LHCSliderRowView {
    NSTextField *_titleLabel;
}

- (instancetype)initWithTitle:(NSString *)title
                     minValue:(double)minValue
                     maxValue:(double)maxValue
                        value:(double)value
                     formatter:(NSString * _Nullable (^)(double))formatter {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _valueFormatter = [formatter copy];

        _titleLabel = [NSTextField labelWithString:title];
        _titleLabel.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
        _titleLabel.textColor = [NSColor secondaryLabelColor];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_titleLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_titleLabel];

        _valueLabel = [NSTextField labelWithString:@""];
        _valueLabel.font = [NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightMedium];
        _valueLabel.textColor = [NSColor secondaryLabelColor];
        _valueLabel.alignment = NSTextAlignmentRight;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_valueLabel setContentHuggingPriority:NSLayoutPriorityRequired
                                forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_valueLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                              forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_valueLabel];

        _slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
        _slider.translatesAutoresizingMaskIntoConstraints = NO;
        _slider.minValue = minValue;
        _slider.maxValue = maxValue;
        _slider.doubleValue = value;
        _slider.continuous = YES;
        _slider.controlSize = NSControlSizeSmall;
        [self addSubview:_slider];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_valueLabel.leadingAnchor
                                                                 constant:-8],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_slider.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_slider.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_slider.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6],
            [_slider.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.heightAnchor constraintEqualToConstant:42]
        ]];

        [self refreshValueLabel];
    }
    return self;
}

- (void)refreshValueLabel {
    if (self.valueFormatter) {
        self.valueLabel.stringValue = self.valueFormatter(self.slider.doubleValue);
    } else {
        self.valueLabel.stringValue = [NSString stringWithFormat:@"%.2f", self.slider.doubleValue];
    }
}

@end

#pragma mark - Beam state

typedef NS_ENUM(NSInteger, LHCBeamState) {
    LHCBeamStateIdle = 0,
    LHCBeamStateInjecting,
    LHCBeamStateCirculating,
    LHCBeamStatePaused,
    LHCBeamStateColliding
};

static const CGFloat LHCZoomNearDistance = 8.0;
static const CGFloat LHCZoomFarDistance = 68.0;
static const CGFloat LHCCameraDragSensitivity = 0.0065;
static const CGFloat LHCCameraMinimumPitch = -0.30;
static const CGFloat LHCCameraMaximumPitch = 1.42;

static CGFloat LHCClamp(CGFloat value, CGFloat lower, CGFloat upper) {
    return MIN(MAX(value, lower), upper);
}

static CGFloat LHCEaseInOut(CGFloat t) {
    return t < 0.5 ? 2.0 * t * t : 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0;
}

static SCNVector3 LHCLerpVector(SCNVector3 from, SCNVector3 to, CGFloat t) {
    return SCNVector3Make(from.x + (to.x - from.x) * t,
                          from.y + (to.y - from.y) * t,
                          from.z + (to.z - from.z) * t);
}

static NSColor *LHCUIColor(CGFloat r, CGFloat g, CGFloat b) {
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1.0];
}

static NSImage *LHCSystemSymbol(NSString *name, CGFloat pointSize) {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    if (!image) {
        return nil;
    }
    NSImageSymbolConfiguration *configuration =
        [NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:NSFontWeightSemibold];
    return [image imageWithSymbolConfiguration:configuration];
}

#pragma mark - Controller

@interface LHCViewController () <SCNSceneRendererDelegate, NSSplitViewDelegate, NSTextViewDelegate>

@property (nonatomic, strong) LHCSimulationConfig *configuration;
@property (nonatomic, strong) LHCHadronModel *model;

@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSVisualEffectView *sidebarView;
@property (nonatomic, strong) NSView *mainView;
@property (nonatomic, strong) LHCSceneView *sceneView;
@property (nonatomic, strong) NSView *collisionFlashView;

@property (nonatomic, strong) NSSegmentedControl *inspectorTabs;
@property (nonatomic, strong) NSScrollView *inspectorScrollView;
@property (nonatomic, strong) NSView *paneHostView;
@property (nonatomic, strong) NSStackView *documentStack;
@property (nonatomic, strong) NSStackView *simulationPane;
@property (nonatomic, strong) NSStackView *modelPane;
@property (nonatomic, strong) NSStackView *collisionPane;
@property (nonatomic, strong) NSStackView *currentPane;

@property (nonatomic, strong) LHCPanelView *statusCard;
@property (nonatomic, strong) NSView *statusDot;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *statusDetailLabel;
@property (nonatomic, strong) NSTextField *energyLabel;

@property (nonatomic, strong) NSButton *centerButton;
@property (nonatomic, strong) LHCProminentButton *playPauseButton;
@property (nonatomic, strong) NSButton *injectButton;
@property (nonatomic, strong) LHCProminentButton *collideButton;
@property (nonatomic, strong) NSButton *resetButton;
@property (nonatomic, strong) NSButton *resetViewButton;
@property (nonatomic, strong) LHCProminentButton *previewButton;

@property (nonatomic, strong) LHCSliderRowView *beamParticleCountRow;
@property (nonatomic, strong) LHCSliderRowView *speedRow;
@property (nonatomic, strong) LHCSliderRowView *zoomRow;
@property (nonatomic, strong) LHCSliderRowView *tunnelOpacityRow;
@property (nonatomic, strong) LHCSliderRowView *detectorScaleRow;
@property (nonatomic, strong) LHCSliderRowView *particleCountRow;
@property (nonatomic, strong) LHCSliderRowView *particleSpreadRow;
@property (nonatomic, strong) LHCSliderRowView *particleLifetimeRow;
@property (nonatomic, strong) LHCSliderRowView *particleVelocityRow;
@property (nonatomic, strong) LHCSliderRowView *particleSizeRow;

@property (nonatomic, strong) NSButton *terrainToggle;
@property (nonatomic, strong) NSButton *tunnelToggle;
@property (nonatomic, strong) NSButton *magnetsToggle;
@property (nonatomic, strong) NSButton *detectorsToggle;
@property (nonatomic, strong) NSButton *labelsToggle;
@property (nonatomic, strong) NSButton *cutawayToggle;

@property (nonatomic, strong) NSPopUpButton *detectorPopup;
@property (nonatomic, strong) NSPopUpButton *presetPopup;
@property (nonatomic, strong) NSTextField *presetDetailLabel;
@property (nonatomic, strong) NSTextField *presetEnergyLabel;
@property (nonatomic, strong) NSTextField *collisionSummaryLabel;

@property (nonatomic, strong) LHCPanelView *selectionCard;
@property (nonatomic, strong) NSTextField *selectionCategoryLabel;
@property (nonatomic, strong) NSTextField *selectionTitleLabel;
@property (nonatomic, strong) NSScrollView *selectionSummaryScrollView;
@property (nonatomic, strong) NSTextView *selectionSummaryTextView;
@property (nonatomic, strong) NSStackView *selectionFactsStack;
@property (nonatomic, strong) LHCPartInfo *selectedPart;

@property (nonatomic) LHCBeamState beamState;
@property (nonatomic) NSTimeInterval lastRenderTime;
@property (nonatomic) NSInteger injectionToken;
@property (nonatomic) NSInteger collisionToken;
@property (nonatomic) BOOL collisionWasPaused;
@property (nonatomic, copy) NSString *collisionEventSummary;
@property (nonatomic, strong) NSMutableArray<SCNNode *> *activeCollisionNodes;
@property (nonatomic) BOOL initialSplitPositionSet;

// Camera state is owned by the controller so orbit, scroll, slider and
// click-to-focus all use the same values.
@property (nonatomic) SCNVector3 cameraOrbitTarget;
@property (nonatomic) CGFloat cameraYaw;
@property (nonatomic) CGFloat cameraPitch;
@property (nonatomic) CGFloat cameraDistance;
@property (nonatomic) CGFloat initialCameraYaw;
@property (nonatomic) CGFloat initialCameraPitch;
@property (nonatomic) CGFloat initialCameraDistance;
@property (nonatomic, strong) NSTimer *cameraAnimationTimer;
@property (nonatomic) NSTimeInterval cameraAnimationStartTime;
@property (nonatomic) NSTimeInterval cameraAnimationDuration;
@property (nonatomic) SCNVector3 cameraAnimationStartTarget;
@property (nonatomic) SCNVector3 cameraAnimationEndTarget;
@property (nonatomic) CGFloat cameraAnimationStartYaw;
@property (nonatomic) CGFloat cameraAnimationEndYaw;
@property (nonatomic) CGFloat cameraAnimationStartPitch;
@property (nonatomic) CGFloat cameraAnimationEndPitch;
@property (nonatomic) CGFloat cameraAnimationStartDistance;
@property (nonatomic) CGFloat cameraAnimationEndDistance;

@end

@implementation LHCViewController

#pragma mark Lifecycle

- (void)loadView {
    self.configuration = [[LHCSimulationConfig alloc] init];
    self.activeCollisionNodes = [NSMutableArray array];
    self.beamState = LHCBeamStateCirculating;

    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1420, 900)];
    root.wantsLayer = YES;
    root.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    self.view = root;

    [self buildInterface];
}

- (void)dealloc {
    [_cameraAnimationTimer invalidate];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.model = [[LHCHadronModel alloc] initWithConfiguration:self.configuration];
    [self.model buildScene];

    [self configureSceneView];
    [self synchronizeInspectorWithConfiguration];
    [self showPartInfo:self.model.partCatalog[@"overview"] partNode:nil];
    [self applyBeamState:LHCBeamStateCirculating];
    [self updateCollisionPresetUI];
    [self updateCollisionSummary];
    [self refreshEnergyLabel];
}

- (void)viewDidAppear {
    [super viewDidAppear];
    if (!self.initialSplitPositionSet) {
        self.initialSplitPositionSet = YES;
        // The split view first settles at its autosaved/initial size.  Position the
        // divider on the next run loop so the sidebar ends up at the intended width.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.view layoutSubtreeIfNeeded];
            CGFloat sidebarWidth = MIN(346.0, MAX(312.0, NSWidth(self.view.bounds) * 0.245));
            [self.splitView setPosition:sidebarWidth ofDividerAtIndex:0];
            [self.splitView adjustSubviews];
        });
    }
    [self.view.window makeFirstResponder:self.sceneView];
}

#pragma mark - Development snapshots

#if DEBUG
- (void)debugSetZoomPercent:(double)percent {
    self.zoomRow.slider.doubleValue = percent;
    [self.zoomRow.slider sendAction:self.zoomRow.slider.action
                                 to:self.zoomRow.slider.target];
    NSLog(@"LHC debug zoom: percent=%.1f distance=%.2f camera=(%.2f, %.2f, %.2f)",
          percent, self.cameraDistance,
          self.model.cameraNode.position.x,
          self.model.cameraNode.position.y,
          self.model.cameraNode.position.z);
}

- (void)debugClickAtPoint:(NSPoint)point {
    NSPoint windowPoint = [self.sceneView convertPoint:point toView:nil];
    NSTimeInterval timestamp = [NSProcessInfo processInfo].systemUptime;
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                       location:windowPoint
                                  modifierFlags:0
                                      timestamp:timestamp
                                   windowNumber:self.sceneView.window.windowNumber
                                        context:nil
                                    eventNumber:0
                                     clickCount:1
                                       pressure:1.0];
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                     location:windowPoint
                                modifierFlags:0
                                    timestamp:timestamp + 0.05
                                 windowNumber:self.sceneView.window.windowNumber
                                      context:nil
                                  eventNumber:1
                                   clickCount:1
                                     pressure:0.0];
    [self.sceneView mouseDown:down];
    [self.sceneView mouseUp:up];
}

- (BOOL)debugFocusPartWithIdentifier:(NSString *)identifier {
    NSDictionary<SCNHitTestOption, id> *options = @{
        SCNHitTestOptionSearchMode: @(SCNHitTestSearchModeAll),
        SCNHitTestOptionBackFaceCulling: @YES
    };
    NSRect bounds = self.sceneView.bounds;
    for (CGFloat y = 0; y < NSHeight(bounds); y += 16.0) {
        for (CGFloat x = 0; x < NSWidth(bounds); x += 16.0) {
            NSPoint point = NSMakePoint(x, y);
            NSArray<SCNHitTestResult *> *results = [self.sceneView hitTest:point options:options];
            for (SCNHitTestResult *result in results) {
                LHCPartInfo *info = [self.model partInfoForHitNode:result.node];
                if ([info.identifier isEqualToString:identifier]) {
                    [self debugClickAtPoint:point];
                    NSLog(@"LHC debug focus: identifier=%@ selected=%@ point=(%.0f, %.0f) target=(%.2f, %.2f, %.2f) distance=%.2f",
                          identifier, self.selectedPart.identifier, point.x, point.y,
                          self.cameraAnimationEndTarget.x,
                          self.cameraAnimationEndTarget.y,
                          self.cameraAnimationEndTarget.z,
                          self.cameraAnimationEndDistance);
                    return YES;
                }
            }
        }
    }
    NSLog(@"LHC debug focus failed: identifier=%@", identifier);
    return NO;
}

- (void)debugApplyOrbitDeltaX:(double)deltaX deltaY:(double)deltaY {
    if (self.sceneView.sceneOrbitHandler) {
        self.sceneView.sceneOrbitHandler(deltaX, deltaY);
    }
    NSLog(@"LHC debug orbit: delta=(%.1f, %.1f) yaw=%.3f pitch=%.3f",
          deltaX, deltaY, self.cameraYaw, self.cameraPitch);
}

- (void)debugApplyScrollZoomDelta:(double)delta {
    if (self.sceneView.sceneZoomHandler) {
        self.sceneView.sceneZoomHandler(delta);
    }
    NSLog(@"LHC debug scroll: delta=%.1f distance=%.2f slider=%.1f",
          delta, self.cameraDistance, self.zoomRow.slider.doubleValue);
}

- (void)debugPerformCenterClick {
    [self.centerButton performClick:nil];
    NSLog(@"LHC debug center: target=(%.2f, %.2f, %.2f) end distance=%.2f",
          self.cameraAnimationEndTarget.x,
          self.cameraAnimationEndTarget.y,
          self.cameraAnimationEndTarget.z,
          self.cameraAnimationEndDistance);
}

- (void)debugStressCenterClicks {
    for (NSInteger i = 0; i < 20; i++) {
        [self.centerButton performClick:nil];
    }
    NSLog(@"LHC debug center stress: 20 clicks completed, timer=%@",
          self.cameraAnimationTimer ? @"running" : @"idle");
}

- (void)debugPerformPreviewClick {
    [self.previewButton performClick:nil];
    NSLog(@"LHC debug preview click: enabled=%@ state=%ld",
          @(self.previewButton.enabled), (long)self.beamState);
}

- (BOOL)writePNGRepresentation:(NSImage *)image toPath:(NSString *)path {
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cgImage) {
        return NO;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [data writeToFile:path atomically:YES];
}

- (BOOL)writeDebugSnapshotToPath:(NSString *)path {
    NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
    NSString *tab = environment[@"LHC_CAPTURE_TAB"];
    if (tab.length > 0) {
        [self selectInspectorTab:tab.integerValue];
    }
    NSString *selectedIdentifier = environment[@"LHC_CAPTURE_SELECT"];
    if (selectedIdentifier.length > 0) {
        LHCPartInfo *info = self.model.partCatalog[selectedIdentifier];
        if (info) {
            [self showPartInfo:info partNode:nil];
            NSLog(@"LHC debug selection: title=%@ category=%@ summary=%@",
                  self.selectionTitleLabel.stringValue,
                  self.selectionCategoryLabel.stringValue,
                  self.selectionSummaryTextView.string);
        }
    }
    if (environment[@"LHC_DEBUG_BEAMS"].boolValue) {
        self.model.terrainNode.hidden = YES;
        self.model.tunnelNode.hidden = YES;
        self.model.magnetsNode.hidden = YES;
        self.model.detectorsNode.hidden = YES;
        [self.model.scene.rootNode childNodeWithName:@"detector.labels" recursively:YES].hidden = YES;
        for (SCNNode *child in self.model.scene.rootNode.childNodes) {
            if ([child.name hasPrefix:@"beam.guide"]) {
                NSLog(@"LHC beam guide %@ hidden=%@ opacity=%.2f position=(%.2f, %.2f, %.2f) geometry=%@ material=%@",
                      child.name, @(child.hidden), child.opacity,
                      child.position.x, child.position.y, child.position.z,
                      child.geometry.class, child.geometry.firstMaterial.emission.contents);
            }
        }
    }
    NSString *cameraOverride = environment[@"LHC_DEBUG_CAMERA"];
    if (cameraOverride.length > 0) {
        NSArray<NSString *> *values = [cameraOverride componentsSeparatedByString:@","];
        if (values.count >= 3) {
            self.model.cameraNode.position = SCNVector3Make(values[0].doubleValue,
                                                             values[1].doubleValue,
                                                             values[2].doubleValue);
            [self.model.cameraNode lookAt:self.model.cameraTarget
                                      up:SCNVector3Make(0, 1, 0)
                              localFront:SCNVector3Make(0, 0, -1)];
        }
        if (values.count >= 4) {
            self.model.cameraNode.camera.fieldOfView = values[3].doubleValue;
        }
    }
    [self.view layoutSubtreeIfNeeded];
    [self.view.window displayIfNeeded];

    NSImage *sceneSnapshot = [self.sceneView snapshot];
    BOOL sceneOK = sceneSnapshot ? [self writePNGRepresentation:sceneSnapshot
                                                         toPath:[path stringByAppendingString:@"-scene.png"]] : NO;

    NSRect bounds = self.view.bounds;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:(NSInteger)MAX(1.0, NSWidth(bounds) * 2.0)
                      pixelsHigh:(NSInteger)MAX(1.0, NSHeight(bounds) * 2.0)
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0
                    bitsPerPixel:0];
    rep.size = bounds.size;
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    [[NSColor colorWithCalibratedWhite:0.08 alpha:1.0] setFill];
    NSRectFill(bounds);
    [self.view displayRectIgnoringOpacity:bounds inContext:context];
    [NSGraphicsContext restoreGraphicsState];
    NSData *uiData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    BOOL uiOK = [uiData writeToFile:[path stringByAppendingString:@"-ui.png"] atomically:YES];

    NSBitmapImageRep *sidebarRep = [self.sidebarView bitmapImageRepForCachingDisplayInRect:self.sidebarView.bounds];
    [self.sidebarView cacheDisplayInRect:self.sidebarView.bounds toBitmapImageRep:sidebarRep];
    NSData *sidebarData = [sidebarRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [sidebarData writeToFile:[path stringByAppendingString:@"-sidebar.png"] atomically:YES];

    NSWindow *window = self.view.window;
    if (window) {
        CGImageRef windowImage = CGWindowListCreateImage(CGRectNull,
                                                         kCGWindowListOptionIncludingWindow,
                                                         (CGWindowID)window.windowNumber,
                                                         kCGWindowImageBoundsIgnoreFraming);
        if (windowImage) {
            NSBitmapImageRep *windowRep = [[NSBitmapImageRep alloc] initWithCGImage:windowImage];
            NSData *windowData = [windowRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            [windowData writeToFile:[path stringByAppendingString:@"-window.png"] atomically:YES];
            CGImageRelease(windowImage);
        }
    }

    NSMutableString *subviewDump = [NSMutableString string];
    for (NSView *view in self.sidebarView.subviews) {
        [subviewDump appendFormat:@"\n  %@ frame=%@ hidden=%@ alpha=%.2f", view.className,
         NSStringFromRect(view.frame), @(view.hidden), view.alphaValue];
    }
    NSLog(@"LHC debug sidebar subviews:%@", subviewDump);

    NSDictionary *previewAttributes = self.previewButton.attributedTitle.length > 0
        ? [self.previewButton.attributedTitle attributesAtIndex:0 effectiveRange:NULL]
        : @{};
    NSLog(@"LHC debug camera: position=(%.2f, %.2f, %.2f) target=(%.2f, %.2f, %.2f) yaw=%.3f pitch=%.3f distance=%.2f fov=%.1f zoom=%.1f",
          self.model.cameraNode.position.x, self.model.cameraNode.position.y, self.model.cameraNode.position.z,
          self.cameraOrbitTarget.x, self.cameraOrbitTarget.y, self.cameraOrbitTarget.z,
          self.cameraYaw, self.cameraPitch, self.cameraDistance,
          self.model.cameraNode.camera.fieldOfView, self.zoomRow.slider.doubleValue);
    NSLog(@"LHC debug preview: enabled=%@ title=%@ color=%@ bezel=%@",
          @(self.previewButton.enabled),
          self.previewButton.attributedTitle.string,
          previewAttributes[NSForegroundColorAttributeName],
          self.previewButton.bezelColor);
    NSLog(@"LHC debug snapshot: view=%@ scene=%@ sidebar=%@ selection=%@ sceneView=%@ window=%@",
          NSStringFromRect(bounds),
          NSStringFromRect(self.sceneView.frame),
          NSStringFromRect(self.sidebarView.frame),
          NSStringFromRect(self.selectionCard.frame),
          NSStringFromRect(self.sceneView.bounds),
          NSStringFromRect(self.view.window.frame));
    NSLog(@"LHC debug ambiguity: sidebar=%@ selection=%@ tabs=%@",
          @(self.sidebarView.hasAmbiguousLayout),
          @(self.selectionCard.hasAmbiguousLayout),
          @(self.inspectorTabs.hasAmbiguousLayout));
    NSLog(@"LHC debug document: %@ content=%@", NSStringFromRect(self.documentStack.frame),
          NSStringFromRect(self.inspectorScrollView.contentView.bounds));
    return sceneOK || uiOK;
}
#endif

#pragma mark Interface assembly

- (void)buildInterface {
    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:self.view.bounds];
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    splitView.vertical = YES;
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    splitView.delegate = self;
    [self.view addSubview:splitView];
    [NSLayoutConstraint activateConstraints:@[
        [splitView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [splitView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [splitView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [splitView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    self.splitView = splitView;

    NSVisualEffectView *sidebar = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 330, NSHeight(self.view.bounds))];
    sidebar.material = NSVisualEffectMaterialSidebar;
    sidebar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    sidebar.state = NSVisualEffectStateActive;
    sidebar.autoresizingMask = NSViewHeightSizable;
    [splitView addArrangedSubview:sidebar];
    self.sidebarView = sidebar;

    NSView *mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(self.view.bounds) - 330, NSHeight(self.view.bounds))];
    mainView.wantsLayer = YES;
    mainView.layer.backgroundColor = [NSColor blackColor].CGColor;
    mainView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [splitView addArrangedSubview:mainView];
    self.mainView = mainView;

    [self buildSidebarContents];
    [self buildSceneArea];
}

- (void)buildSidebarContents {
    NSView *sidebar = self.sidebarView;

    // Brand / header
    NSImageView *appIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    appIcon.translatesAutoresizingMaskIntoConstraints = NO;
    appIcon.image = [NSApplication sharedApplication].applicationIconImage;
    appIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
    appIcon.wantsLayer = YES;
    appIcon.layer.cornerRadius = 9;
    appIcon.layer.masksToBounds = YES;
    [NSLayoutConstraint activateConstraints:@[
        [appIcon.widthAnchor constraintEqualToConstant:42],
        [appIcon.heightAnchor constraintEqualToConstant:42]
    ]];

    NSTextField *title = [NSTextField labelWithString:@"LHC"];
    title.font = [NSFont systemFontOfSize:23 weight:NSFontWeightBold];
    title.textColor = [NSColor labelColor];

    NSTextField *subtitle = [NSTextField labelWithString:@"INTERACTIVE COLLIDER"];
    subtitle.attributedStringValue = [[NSAttributedString alloc]
        initWithString:@"INTERACTIVE COLLIDER"
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:9.0 weight:NSFontWeightSemibold],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
                NSKernAttributeName: @1.35
            }];

    NSStackView *titleStack = [NSStackView stackViewWithViews:@[title, subtitle]];
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = 1;
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *header = [NSStackView stackViewWithViews:@[appIcon, titleStack]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 11;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar addSubview:header];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:17],
        [header.trailingAnchor constraintLessThanOrEqualToAnchor:sidebar.trailingAnchor constant:-17],
        [header.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:19]
    ]];

    self.inspectorTabs = [NSSegmentedControl segmentedControlWithLabels:@[@"Simulate", @"Model", @"Collisions"]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne
                                                               target:self
                                                               action:@selector(inspectorTabChanged:)];
    self.inspectorTabs.translatesAutoresizingMaskIntoConstraints = NO;
    self.inspectorTabs.segmentDistribution = NSSegmentDistributionFillEqually;
    self.inspectorTabs.selectedSegment = 0;
    self.inspectorTabs.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
    [sidebar addSubview:self.inspectorTabs];
    [NSLayoutConstraint activateConstraints:@[
        [self.inspectorTabs.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16],
        [self.inspectorTabs.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-16],
        [self.inspectorTabs.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:16],
        [self.inspectorTabs.heightAnchor constraintEqualToConstant:26]
    ]];

    // Scrollable tab content
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.horizontalScrollElasticity = NSScrollElasticityNone;
    [sidebar addSubview:scrollView];
    self.inspectorScrollView = scrollView;

    LHCFlippedView *documentView = [[LHCFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 320, 500)];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = documentView;
    [NSLayoutConstraint activateConstraints:@[
        [documentView.leadingAnchor constraintEqualToAnchor:scrollView.contentView.leadingAnchor],
        [documentView.topAnchor constraintEqualToAnchor:scrollView.contentView.topAnchor],
        [documentView.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor]
    ]];

    NSStackView *documentStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    documentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    documentStack.alignment = NSLayoutAttributeLeading;
    documentStack.spacing = 18;
    documentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView addSubview:documentStack];
    [NSLayoutConstraint activateConstraints:@[
        [documentStack.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor constant:16],
        [documentStack.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor constant:-16],
        [documentStack.topAnchor constraintEqualToAnchor:documentView.topAnchor constant:4],
        [documentStack.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor constant:-16]
    ]];
    self.documentStack = documentStack;

    self.paneHostView = [[NSView alloc] initWithFrame:NSZeroRect];
    self.paneHostView.translatesAutoresizingMaskIntoConstraints = NO;
    [documentStack addArrangedSubview:self.paneHostView];
    [self.paneHostView.widthAnchor constraintEqualToAnchor:documentStack.widthAnchor].active = YES;

    self.simulationPane = [self buildSimulationPane];
    self.modelPane = [self buildModelPane];
    self.collisionPane = [self buildCollisionPane];
    [self showInspectorPane:self.simulationPane scrollToTop:YES];

    // Fixed selection inspector at the foot of the sidebar.
    self.selectionCard = [self buildSelectionCard];
    [sidebar addSubview:self.selectionCard];
    [NSLayoutConstraint activateConstraints:@[
        [self.selectionCard.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16],
        [self.selectionCard.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-16],
        [self.selectionCard.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor constant:-14],
        [self.selectionCard.heightAnchor constraintEqualToConstant:238],
        [scrollView.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:self.inspectorTabs.bottomAnchor constant:9],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.selectionCard.topAnchor constant:-12]
    ]];
}

- (void)buildSceneArea {
    NSView *mainView = self.mainView;

    LHCSceneView *sceneView = [[LHCSceneView alloc] initWithFrame:NSZeroRect];
    sceneView.translatesAutoresizingMaskIntoConstraints = NO;
    // The controller owns the camera so orbit, scroll, slider and focus
    // animations always agree with each other.
    sceneView.allowsCameraControl = NO;
    sceneView.autoenablesDefaultLighting = NO;
    sceneView.antialiasingMode = SCNAntialiasingModeMultisampling4X;
    sceneView.preferredFramesPerSecond = 60;
    sceneView.rendersContinuously = YES;
    sceneView.playing = YES;
    sceneView.backgroundColor = [NSColor blackColor];
    sceneView.jitteringEnabled = NO;
    sceneView.toolTip = @"Drag to orbit. Scroll to zoom. Click a detector, magnet or label to inspect and focus on it.";
    [mainView addSubview:sceneView];
    [NSLayoutConstraint activateConstraints:@[
        [sceneView.leadingAnchor constraintEqualToAnchor:mainView.leadingAnchor],
        [sceneView.trailingAnchor constraintEqualToAnchor:mainView.trailingAnchor],
        [sceneView.topAnchor constraintEqualToAnchor:mainView.topAnchor],
        [sceneView.bottomAnchor constraintEqualToAnchor:mainView.bottomAnchor]
    ]];
    self.sceneView = sceneView;

    __weak typeof(self) weakSelf = self;
    sceneView.sceneClickHandler = ^(NSPoint pointInView) {
        [weakSelf handleSceneClickAtPoint:pointInView];
    };
    sceneView.sceneOrbitHandler = ^(CGFloat deltaX, CGFloat deltaY) {
        [weakSelf handleSceneOrbitDeltaX:deltaX deltaY:deltaY];
    };
    sceneView.sceneZoomHandler = ^(CGFloat delta) {
        [weakSelf handleSceneZoomDelta:delta];
    };

    LHCMouseTransparentView *flashView = [[LHCMouseTransparentView alloc] initWithFrame:NSZeroRect];
    flashView.translatesAutoresizingMaskIntoConstraints = NO;
    flashView.alphaValue = 0.0;
    flashView.hidden = YES;
    [mainView addSubview:flashView];
    [NSLayoutConstraint activateConstraints:@[
        [flashView.leadingAnchor constraintEqualToAnchor:mainView.leadingAnchor],
        [flashView.trailingAnchor constraintEqualToAnchor:mainView.trailingAnchor],
        [flashView.topAnchor constraintEqualToAnchor:mainView.topAnchor],
        [flashView.bottomAnchor constraintEqualToAnchor:mainView.bottomAnchor]
    ]];
    self.collisionFlashView = flashView;

    // Live badge
    LHCPassThroughEffectView *liveBadge = [self effectPillWithMaterial:NSVisualEffectMaterialHUDWindow];
    NSView *liveDot = [self colorDot:LHCUIColor(0.30, 0.95, 0.62) diameter:6];
    NSTextField *liveLabel = [NSTextField labelWithString:@"LIVE 3D  ·  CLICK TO INSPECT & FOCUS"];
    liveLabel.attributedStringValue = [[NSAttributedString alloc]
        initWithString:@"LIVE 3D  ·  CLICK TO INSPECT & FOCUS"
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:9.0 weight:NSFontWeightSemibold],
                NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:1.0 alpha:0.82],
                NSKernAttributeName: @1.0
            }];
    NSStackView *liveStack = [NSStackView stackViewWithViews:@[liveDot, liveLabel]];
    liveStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    liveStack.alignment = NSLayoutAttributeCenterY;
    liveStack.spacing = 7;
    liveStack.translatesAutoresizingMaskIntoConstraints = NO;
    [liveBadge addSubview:liveStack];
    [mainView addSubview:liveBadge];
    [NSLayoutConstraint activateConstraints:@[
        [liveStack.leadingAnchor constraintEqualToAnchor:liveBadge.leadingAnchor constant:11],
        [liveStack.trailingAnchor constraintEqualToAnchor:liveBadge.trailingAnchor constant:-12],
        [liveStack.centerYAnchor constraintEqualToAnchor:liveBadge.centerYAnchor],
        [liveBadge.leadingAnchor constraintEqualToAnchor:mainView.leadingAnchor constant:18],
        [liveBadge.topAnchor constraintEqualToAnchor:mainView.topAnchor constant:16],
        [liveBadge.heightAnchor constraintEqualToConstant:27]
    ]];

    // Interaction hint
    LHCPassThroughEffectView *hintView = [self effectPillWithMaterial:NSVisualEffectMaterialHUDWindow];
    NSTextField *hintLabel = [NSTextField labelWithString:@"Drag to orbit   ·   Scroll to zoom   ·   Click a component to inspect & focus"];
    hintLabel.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular];
    hintLabel.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.70];
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [hintView addSubview:hintLabel];
    [mainView addSubview:hintView];
    [NSLayoutConstraint activateConstraints:@[
        [hintLabel.leadingAnchor constraintEqualToAnchor:hintView.leadingAnchor constant:13],
        [hintLabel.trailingAnchor constraintEqualToAnchor:hintView.trailingAnchor constant:-13],
        [hintLabel.centerYAnchor constraintEqualToAnchor:hintView.centerYAnchor],
        [hintView.centerXAnchor constraintEqualToAnchor:mainView.centerXAnchor],
        [hintView.bottomAnchor constraintEqualToAnchor:mainView.bottomAnchor constant:-16],
        [hintView.heightAnchor constraintEqualToConstant:29]
    ]];

    // Center-view control, kept on the canvas for quick access after orbiting.
    NSVisualEffectView *centerPill = [self interactivePillWithMaterial:NSVisualEffectMaterialHUDWindow];
    NSButton *centerButton = [NSButton buttonWithTitle:@"Center View"
                                                target:self
                                                action:@selector(resetCamera:)];
    centerButton.translatesAutoresizingMaskIntoConstraints = NO;
    centerButton.bordered = NO;
    centerButton.image = LHCSystemSymbol(@"viewfinder", 11.0);
    centerButton.imagePosition = NSImageLeading;
    centerButton.imageScaling = NSImageScaleProportionallyDown;
    centerButton.contentTintColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.92];
    centerButton.attributedTitle = [[NSAttributedString alloc]
        initWithString:@"Center View"
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold],
                NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:1.0 alpha:0.92]
            }];
    centerButton.toolTip = @"Center the LHC model in the viewport (⌘0)";
    centerButton.accessibilityLabel = @"Center View";
    self.centerButton = centerButton;
    [centerPill addSubview:centerButton];
    [mainView addSubview:centerPill];
    [NSLayoutConstraint activateConstraints:@[
        [centerButton.leadingAnchor constraintEqualToAnchor:centerPill.leadingAnchor constant:12],
        [centerButton.trailingAnchor constraintEqualToAnchor:centerPill.trailingAnchor constant:-12],
        [centerButton.topAnchor constraintEqualToAnchor:centerPill.topAnchor],
        [centerButton.bottomAnchor constraintEqualToAnchor:centerPill.bottomAnchor],
        [centerPill.trailingAnchor constraintEqualToAnchor:mainView.trailingAnchor constant:-18],
        [centerPill.topAnchor constraintEqualToAnchor:mainView.topAnchor constant:16],
        [centerPill.heightAnchor constraintEqualToConstant:27]
    ]];
}

- (LHCPassThroughEffectView *)effectPillWithMaterial:(NSVisualEffectMaterial)material {
    LHCPassThroughEffectView *view = [[LHCPassThroughEffectView alloc] initWithFrame:NSZeroRect];
    [self styleEffectPill:view material:material];
    return view;
}

- (NSVisualEffectView *)interactivePillWithMaterial:(NSVisualEffectMaterial)material {
    NSVisualEffectView *view = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    [self styleEffectPill:view material:material];
    return view;
}

- (void)styleEffectPill:(NSVisualEffectView *)view material:(NSVisualEffectMaterial)material {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.material = material;
    view.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    view.state = NSVisualEffectStateActive;
    view.wantsLayer = YES;
    view.layer.cornerRadius = 8;
    view.layer.masksToBounds = YES;
}

- (NSView *)colorDot:(NSColor *)color diameter:(CGFloat)diameter {
    NSView *dot = [[NSView alloc] initWithFrame:NSZeroRect];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.wantsLayer = YES;
    dot.layer.cornerRadius = diameter / 2.0;
    dot.layer.backgroundColor = color.CGColor;
    [NSLayoutConstraint activateConstraints:@[
        [dot.widthAnchor constraintEqualToConstant:diameter],
        [dot.heightAnchor constraintEqualToConstant:diameter]
    ]];
    return dot;
}

#pragma mark Inspector panes

- (NSStackView *)newPaneStack {
    NSStackView *pane = [[NSStackView alloc] initWithFrame:NSZeroRect];
    pane.orientation = NSUserInterfaceLayoutOrientationVertical;
    pane.alignment = NSLayoutAttributeLeading;
    pane.spacing = 20;
    pane.translatesAutoresizingMaskIntoConstraints = NO;
    return pane;
}

- (NSTextField *)sectionHeaderLabel:(NSString *)title {
    NSTextField *label = [NSTextField labelWithString:[title uppercaseString]];
    label.attributedStringValue = [[NSAttributedString alloc]
        initWithString:[title uppercaseString]
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:9.5 weight:NSFontWeightSemibold],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
                NSKernAttributeName: @1.15
            }];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSStackView *)newSectionWithTitle:(NSString *)title {
    NSStackView *section = [[NSStackView alloc] initWithFrame:NSZeroRect];
    section.orientation = NSUserInterfaceLayoutOrientationVertical;
    section.alignment = NSLayoutAttributeLeading;
    section.spacing = 8;
    section.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *header = [self sectionHeaderLabel:title];
    [section addArrangedSubview:header];
    [header.widthAnchor constraintEqualToAnchor:section.widthAnchor].active = YES;
    return section;
}

- (void)addFullWidthView:(NSView *)view toStack:(NSStackView *)stack {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}

- (void)addSection:(NSStackView *)section toPane:(NSStackView *)pane {
    section.translatesAutoresizingMaskIntoConstraints = NO;
    [pane addArrangedSubview:section];
    [section.widthAnchor constraintEqualToAnchor:pane.widthAnchor].active = YES;
}

- (NSTextField *)wrappingLabelWithString:(NSString *)string
                                   font:(NSFont *)font
                                  color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:string];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 0;
    label.cell.wraps = YES;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                    forOrientation:NSLayoutConstraintOrientationVertical];
    return label;
}

- (NSButton *)actionButtonWithTitle:(NSString *)title
                             symbol:(NSString *)symbol
                            tooltip:(NSString *)tooltip
                             action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStylePush;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    button.toolTip = tooltip;
    if (symbol.length > 0) {
        button.image = LHCSystemSymbol(symbol, 12.0);
        button.imagePosition = NSImageLeading;
    }
    [button.heightAnchor constraintEqualToConstant:31].active = YES;
    return button;
}

- (LHCProminentButton *)prominentButtonWithTitle:(NSString *)title
                                          symbol:(NSString *)symbol
                                         tooltip:(NSString *)tooltip
                                          action:(SEL)action {
    LHCProminentButton *button = [LHCProminentButton buttonWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStylePush;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    button.toolTip = tooltip;
    [button.heightAnchor constraintEqualToConstant:31].active = YES;
    [button applyProminentTitle:title symbol:symbol color:[NSColor controlAccentColor]];
    return button;
}

- (void)updateProminentButton:(NSButton *)button
                        title:(NSString *)title
                       symbol:(NSString *)symbol
                        color:(NSColor *)color {
    if ([button isKindOfClass:[LHCProminentButton class]]) {
        [(LHCProminentButton *)button applyProminentTitle:title symbol:symbol color:color];
        return;
    }

    // Fallback for ordinary buttons.
    button.bezelColor = color;
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    button.attributedTitle = [[NSAttributedString alloc]
        initWithString:title
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold],
                NSForegroundColorAttributeName: [NSColor whiteColor],
                NSParagraphStyleAttributeName: paragraph
            }];
}

- (NSStackView *)horizontalButtonRowWithViews:(NSArray<NSView *> *)views {
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.distribution = NSStackViewDistributionFillEqually;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    return row;
}

- (NSStackView *)buildSimulationPane {
    NSStackView *pane = [self newPaneStack];

    // Beam status card
    NSStackView *statusSection = [self newSectionWithTitle:@"Beam status"];
    LHCPanelView *statusCard = [[LHCPanelView alloc] initWithFrame:NSZeroRect];
    statusCard.translatesAutoresizingMaskIntoConstraints = NO;
    statusCard.accentColor = [NSColor systemGreenColor];
    self.statusCard = statusCard;
    [statusCard.heightAnchor constraintEqualToConstant:102].active = YES;

    NSView *dot = [self colorDot:[NSColor systemGreenColor] diameter:8];
    self.statusDot = dot;
    [statusCard addSubview:dot];

    NSTextField *statusLabel = [NSTextField labelWithString:@"Circulating"];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    statusLabel.textColor = [NSColor labelColor];
    self.statusLabel = statusLabel;
    [statusCard addSubview:statusLabel];

    NSTextField *detail = [self wrappingLabelWithString:@"Two counter-rotating beams"
                                                   font:[NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular]
                                                  color:[NSColor secondaryLabelColor]];
    self.statusDetailLabel = detail;
    [statusCard addSubview:detail];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.boxType = NSBoxSeparator;
    [statusCard addSubview:separator];

    NSTextField *energy = [NSTextField labelWithString:@"6.8 TeV / beam  ·  13.6 TeV collision"];
    energy.translatesAutoresizingMaskIntoConstraints = NO;
    energy.font = [NSFont monospacedDigitSystemFontOfSize:10.0 weight:NSFontWeightRegular];
    energy.textColor = [NSColor secondaryLabelColor];
    energy.lineBreakMode = NSLineBreakByTruncatingTail;
    self.energyLabel = energy;
    [statusCard addSubview:energy];

    [NSLayoutConstraint activateConstraints:@[
        [dot.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16],
        [dot.centerYAnchor constraintEqualToAnchor:statusLabel.centerYAnchor],
        [statusLabel.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:8],
        [statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:statusCard.trailingAnchor constant:-14],
        [statusLabel.topAnchor constraintEqualToAnchor:statusCard.topAnchor constant:14],
        [detail.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16],
        [detail.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-14],
        [detail.topAnchor constraintEqualToAnchor:statusLabel.bottomAnchor constant:2],
        [separator.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16],
        [separator.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-16],
        [separator.topAnchor constraintEqualToAnchor:detail.bottomAnchor constant:8],
        [energy.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16],
        [energy.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-14],
        [energy.topAnchor constraintEqualToAnchor:separator.bottomAnchor constant:8]
    ]];
    [self addFullWidthView:statusCard toStack:statusSection];
    [self addSection:statusSection toPane:pane];

    // Run controls
    NSStackView *runSection = [self newSectionWithTitle:@"Simulation"];

    self.playPauseButton = [self prominentButtonWithTitle:@"Pause Beams"
                                                   symbol:@"pause.fill"
                                                  tooltip:@"Pause or resume the orbiting bunches and tracers (Space)"
                                                   action:@selector(togglePlayPause:)];
    [self addFullWidthView:self.playPauseButton toStack:runSection];

    self.injectButton = [self actionButtonWithTitle:@"Inject Beam"
                                             symbol:@"arrow.down.circle.fill"
                                            tooltip:@"Reset the bunch phases and inject fresh beams"
                                             action:@selector(injectBeam:)];
    self.collideButton = [self prominentButtonWithTitle:@"Collide"
                                                 symbol:@"bolt.fill"
                                                tooltip:@"Bring the beams together at the selected interaction point"
                                                 action:@selector(collideBeams:)];
    [self updateProminentButton:self.collideButton
                          title:@"Collide"
                         symbol:@"bolt.fill"
                          color:[NSColor systemRedColor]];
    NSStackView *actionRow = [self horizontalButtonRowWithViews:@[self.injectButton, self.collideButton]];
    [self addFullWidthView:actionRow toStack:runSection];

    self.resetButton = [self actionButtonWithTitle:@"Reset"
                                            symbol:@"arrow.counterclockwise"
                                           tooltip:@"Reset beam speed, particle count, energy and phase"
                                            action:@selector(resetSimulation:)];
    self.resetViewButton = [self actionButtonWithTitle:@"Center View"
                                                symbol:@"viewfinder"
                                               tooltip:@"Center the LHC model and restore the default camera (⌘0)"
                                                action:@selector(resetCamera:)];
    self.resetButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    self.resetViewButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    NSStackView *utilityRow = [self horizontalButtonRowWithViews:@[self.resetButton, self.resetViewButton]];
    [self addFullWidthView:utilityRow toStack:runSection];
    [self addSection:runSection toPane:pane];

    // Beam settings
    NSStackView *beamSection = [self newSectionWithTitle:@"Beam settings"];
    self.beamParticleCountRow = [[LHCSliderRowView alloc] initWithTitle:@"Particles per beam"
                                                               minValue:1.0
                                                               maxValue:8.0
                                                                  value:self.configuration.beamParticleCount
                                                              formatter:^NSString *(double value) {
        return [NSString stringWithFormat:@"%ld", (long)llround(value)];
    }];
    self.beamParticleCountRow.slider.numberOfTickMarks = 8;
    self.beamParticleCountRow.slider.allowsTickMarkValuesOnly = YES;
    self.beamParticleCountRow.slider.toolTip = @"Bright tracer particles circulating in each beam";
    self.beamParticleCountRow.slider.target = self;
    self.beamParticleCountRow.slider.action = @selector(beamParticleCountChanged:);
    [self addFullWidthView:self.beamParticleCountRow toStack:beamSection];

    self.speedRow = [[LHCSliderRowView alloc] initWithTitle:@"Particle speed"
                                                    minValue:0.2
                                                    maxValue:2.5
                                                       value:self.configuration.beamSpeed
                                                   formatter:^NSString *(double value) {
        return [NSString stringWithFormat:@"%.1f×", value];
    }];
    self.speedRow.slider.toolTip = @"Orbital speed of the beam particles";
    self.speedRow.slider.target = self;
    self.speedRow.slider.action = @selector(beamSpeedChanged:);
    [self addFullWidthView:self.speedRow toStack:beamSection];

    NSTextField *targetLabel = [NSTextField labelWithString:@"Collision point"];
    targetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    targetLabel.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    targetLabel.textColor = [NSColor secondaryLabelColor];
    [self addFullWidthView:targetLabel toStack:beamSection];

    self.detectorPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.detectorPopup.translatesAutoresizingMaskIntoConstraints = NO;
    self.detectorPopup.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    NSArray<NSArray<NSString *> *> *detectorTitles = @[
        @[@"ATLAS (IP1)", @"atlas"],
        @[@"CMS (IP5)", @"cms"],
        @[@"ALICE (IP2)", @"alice"],
        @[@"LHCb (IP8)", @"lhcb"]
    ];
    for (NSArray<NSString *> *pair in detectorTitles) {
        [self.detectorPopup addItemWithTitle:pair[0]];
        self.detectorPopup.lastItem.representedObject = pair[1];
    }
    self.detectorPopup.target = self;
    self.detectorPopup.action = @selector(collisionTargetChanged:);
    [self addFullWidthView:self.detectorPopup toStack:beamSection];
    [self addSection:beamSection toPane:pane];

    // Camera
    NSStackView *cameraSection = [self newSectionWithTitle:@"Camera"];
    self.zoomRow = [[LHCSliderRowView alloc] initWithTitle:@"Zoom"
                                                   minValue:0.0
                                                   maxValue:100.0
                                                      value:50.0
                                                  formatter:^NSString *(double value) {
        return [NSString stringWithFormat:@"%.0f%%", value];
    }];
    self.zoomRow.slider.target = self;
    self.zoomRow.slider.action = @selector(zoomChanged:);
    [self addFullWidthView:self.zoomRow toStack:cameraSection];
    [self addSection:cameraSection toPane:pane];

    // Quick tip
    LHCPanelView *tipCard = [[LHCPanelView alloc] initWithFrame:NSZeroRect];
    tipCard.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *tip = [self wrappingLabelWithString:@"Tip: click a detector, a coloured magnet or its floating label in the 3D view. The inspector below updates with the physics behind it."
                                                font:[NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular]
                                               color:[NSColor secondaryLabelColor]];
    [tipCard addSubview:tip];
    [NSLayoutConstraint activateConstraints:@[
        [tip.leadingAnchor constraintEqualToAnchor:tipCard.leadingAnchor constant:13],
        [tip.trailingAnchor constraintEqualToAnchor:tipCard.trailingAnchor constant:-13],
        [tip.topAnchor constraintEqualToAnchor:tipCard.topAnchor constant:11],
        [tip.bottomAnchor constraintEqualToAnchor:tipCard.bottomAnchor constant:-11]
    ]];
    [self addFullWidthView:tipCard toStack:pane];

    return pane;
}

- (NSButton *)checkboxWithTitle:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton checkboxWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    button.toolTip = title;
    return button;
}

- (NSStackView *)buildModelPane {
    NSStackView *pane = [self newPaneStack];

    NSTextField *intro = [self wrappingLabelWithString:@"Every component is generated with SceneKit primitives at launch. Reconfigure the exhibit here; the geometry updates live."
                                                 font:[NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular]
                                                color:[NSColor secondaryLabelColor]];
    [self addFullWidthView:intro toStack:pane];

    NSStackView *componentsSection = [self newSectionWithTitle:@"Visible components"];
    self.terrainToggle = [self checkboxWithTitle:@"Terrain & survey plateau" action:@selector(modelOptionChanged:)];
    self.tunnelToggle = [self checkboxWithTitle:@"Beam tunnel & vacuum" action:@selector(modelOptionChanged:)];
    self.magnetsToggle = [self checkboxWithTitle:@"Magnet lattice" action:@selector(modelOptionChanged:)];
    self.detectorsToggle = [self checkboxWithTitle:@"Particle detectors" action:@selector(modelOptionChanged:)];
    self.labelsToggle = [self checkboxWithTitle:@"Detector labels" action:@selector(modelOptionChanged:)];
    for (NSButton *toggle in @[self.terrainToggle, self.tunnelToggle, self.magnetsToggle,
                               self.detectorsToggle, self.labelsToggle]) {
        [self addFullWidthView:toggle toStack:componentsSection];
    }
    [self addSection:componentsSection toPane:pane];

    NSStackView *geometrySection = [self newSectionWithTitle:@"Geometry"];
    self.cutawayToggle = [self checkboxWithTitle:@"Cutaway view · reveal detector interiors"
                                           action:@selector(modelOptionChanged:)];
    [self addFullWidthView:self.cutawayToggle toStack:geometrySection];

    self.tunnelOpacityRow = [[LHCSliderRowView alloc] initWithTitle:@"Tunnel transparency"
                                                           minValue:8.0
                                                           maxValue:85.0
                                                              value:self.configuration.tunnelOpacity * 100.0
                                                          formatter:^NSString *(double value) {
        return [NSString stringWithFormat:@"%.0f%%", value];
    }];
    self.tunnelOpacityRow.slider.target = self;
    self.tunnelOpacityRow.slider.action = @selector(tunnelOpacityChanged:);
    [self addFullWidthView:self.tunnelOpacityRow toStack:geometrySection];

    self.detectorScaleRow = [[LHCSliderRowView alloc] initWithTitle:@"Detector footprint"
                                                           minValue:70.0
                                                           maxValue:140.0
                                                              value:self.configuration.detectorScale * 100.0
                                                          formatter:^NSString *(double value) {
        return [NSString stringWithFormat:@"%.2f×", value / 100.0];
    }];
    self.detectorScaleRow.slider.target = self;
    self.detectorScaleRow.slider.action = @selector(detectorScaleChanged:);
    [self addFullWidthView:self.detectorScaleRow toStack:geometrySection];
    [self addSection:geometrySection toPane:pane];

    // Colour key
    NSStackView *legendSection = [self newSectionWithTitle:@"Colour key"];
    NSArray<NSArray *> *legend = @[
        @[LHCUIColor(0.18, 0.52, 1.0), @"Dipole bending magnets"],
        @[LHCUIColor(0.96, 0.24, 0.28), @"Quadrupole focusing magnets"],
        @[LHCUIColor(0.31, 0.92, 1.0), @"Beam A · clockwise"],
        @[LHCUIColor(1.0, 0.32, 0.82), @"Beam B · anticlockwise"]
    ];
    for (NSArray *entry in legend) {
        NSView *legendDot = [self colorDot:entry[0] diameter:8];
        NSTextField *legendLabel = [NSTextField labelWithString:entry[1]];
        legendLabel.translatesAutoresizingMaskIntoConstraints = NO;
        legendLabel.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
        legendLabel.textColor = [NSColor secondaryLabelColor];
        [legendLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *row = [NSStackView stackViewWithViews:@[legendDot, legendLabel]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeCenterY;
        row.spacing = 8;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self addFullWidthView:row toStack:legendSection];
    }
    [self addSection:legendSection toPane:pane];

    NSStackView *resetSection = [self newSectionWithTitle:@"Reset"];
    NSButton *resetModel = [self actionButtonWithTitle:@"Reset Model Options"
                                                symbol:@"arrow.counterclockwise"
                                               tooltip:@"Restore visibility, cutaway and geometry defaults"
                                                action:@selector(resetModelOptions:)];
    resetModel.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    [self addFullWidthView:resetModel toStack:resetSection];
    [self addSection:resetSection toPane:pane];

    LHCPanelView *noteCard = [[LHCPanelView alloc] initWithFrame:NSZeroRect];
    noteCard.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *note = [self wrappingLabelWithString:@"The detector forms are informed by the CERN / University of Liverpool papercraft instructions in the project’s images folder. Height stays locked to the beamline when the footprint scale changes."
                                                 font:[NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular]
                                                color:[NSColor secondaryLabelColor]];
    [noteCard addSubview:note];
    [NSLayoutConstraint activateConstraints:@[
        [note.leadingAnchor constraintEqualToAnchor:noteCard.leadingAnchor constant:13],
        [note.trailingAnchor constraintEqualToAnchor:noteCard.trailingAnchor constant:-13],
        [note.topAnchor constraintEqualToAnchor:noteCard.topAnchor constant:11],
        [note.bottomAnchor constraintEqualToAnchor:noteCard.bottomAnchor constant:-11]
    ]];
    [self addFullWidthView:noteCard toStack:pane];

    return pane;
}

- (NSStackView *)buildCollisionPane {
    NSStackView *pane = [self newPaneStack];

    NSTextField *intro = [self wrappingLabelWithString:@"Tune the event display. These particle systems are a stylised reconstruction, not a physics calculation."
                                                 font:[NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular]
                                                color:[NSColor secondaryLabelColor]];
    [self addFullWidthView:intro toStack:pane];

    NSStackView *eventSection = [self newSectionWithTitle:@"Event type"];
    self.presetPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.presetPopup.translatesAutoresizingMaskIntoConstraints = NO;
    self.presetPopup.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    for (LHCCollisionPreset *preset in [LHCCollisionPreset presets]) {
        [self.presetPopup addItemWithTitle:preset.name];
    }
    self.presetPopup.target = self;
    self.presetPopup.action = @selector(collisionPresetChanged:);
    [self addFullWidthView:self.presetPopup toStack:eventSection];

    self.presetEnergyLabel = [NSTextField labelWithString:@""];
    self.presetEnergyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.presetEnergyLabel.font = [NSFont monospacedDigitSystemFontOfSize:10.0 weight:NSFontWeightMedium];
    self.presetEnergyLabel.textColor = [NSColor secondaryLabelColor];
    [self addFullWidthView:self.presetEnergyLabel toStack:eventSection];

    self.presetDetailLabel = [self wrappingLabelWithString:@""
                                                      font:[NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular]
                                                     color:[NSColor secondaryLabelColor]];
    [self addFullWidthView:self.presetDetailLabel toStack:eventSection];

    self.collisionSummaryLabel = [NSTextField labelWithString:@""];
    self.collisionSummaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.collisionSummaryLabel.font = [NSFont monospacedDigitSystemFontOfSize:9.5 weight:NSFontWeightRegular];
    self.collisionSummaryLabel.textColor = [NSColor tertiaryLabelColor];
    self.collisionSummaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addFullWidthView:self.collisionSummaryLabel toStack:eventSection];
    [self addSection:eventSection toPane:pane];

    NSStackView *particleSection = [self newSectionWithTitle:@"Particle configuration"];
    self.particleCountRow = [[LHCSliderRowView alloc] initWithTitle:@"Particles per event"
                                                           minValue:120.0
                                                           maxValue:3000.0
                                                              value:self.configuration.particleCount
                                                          formatter:^NSString *(double value) {
        return [NSString stringWithFormat:@"%ld", (long)llround(value)];
    }];
    self.particleCountRow.slider.target = self;
    self.particleCountRow.slider.action = @selector(particleSettingsChanged:);
    [self addFullWidthView:self.particleCountRow toStack:particleSection];

    self.particleSpreadRow = [[LHCSliderRowView alloc] initWithTitle:@"Emission spread"
                                                            minValue:20.0
                                                            maxValue:180.0
                                                               value:self.configuration.particleSpread
                                                           formatter:^NSString *(double value) {
        return [NSString stringWithFormat:@"%.0f°", value];
    }];
    self.particleSpreadRow.slider.target = self;
    self.particleSpreadRow.slider.action = @selector(particleSettingsChanged:);
    [self addFullWidthView:self.particleSpreadRow toStack:particleSection];

    self.particleLifetimeRow = [[LHCSliderRowView alloc] initWithTitle:@"Particle lifetime"
                                                              minValue:0.5
                                                              maxValue:4.0
                                                                 value:self.configuration.particleLifetime
                                                             formatter:^NSString *(double value) {
        return [NSString stringWithFormat:@"%.1f s", value];
    }];
    self.particleLifetimeRow.slider.target = self;
    self.particleLifetimeRow.slider.action = @selector(particleSettingsChanged:);
    [self addFullWidthView:self.particleLifetimeRow toStack:particleSection];

    self.particleVelocityRow = [[LHCSliderRowView alloc] initWithTitle:@"Particle velocity"
                                                              minValue:1.0
                                                              maxValue:20.0
                                                                 value:self.configuration.particleVelocity
                                                             formatter:^NSString *(double value) {
        return [NSString stringWithFormat:@"%.1f u/s", value];
    }];
    self.particleVelocityRow.slider.target = self;
    self.particleVelocityRow.slider.action = @selector(particleSettingsChanged:);
    [self addFullWidthView:self.particleVelocityRow toStack:particleSection];

    self.particleSizeRow = [[LHCSliderRowView alloc] initWithTitle:@"Particle size"
                                                          minValue:0.02
                                                          maxValue:0.35
                                                             value:self.configuration.particleSize
                                                         formatter:^NSString *(double value) {
        return [NSString stringWithFormat:@"%.3f", value];
    }];
    self.particleSizeRow.slider.target = self;
    self.particleSizeRow.slider.action = @selector(particleSettingsChanged:);
    [self addFullWidthView:self.particleSizeRow toStack:particleSection];
    [self addSection:particleSection toPane:pane];

    NSStackView *previewSection = [self newSectionWithTitle:@"Preview"];
    self.previewButton = [self prominentButtonWithTitle:@"Test burst at ATLAS"
                                                 symbol:@"sparkles"
                                                tooltip:@"Run the configured collision effect at the selected interaction point"
                                                 action:@selector(collideBeams:)];
    [self updateProminentButton:self.previewButton
                          title:@"Test burst at ATLAS"
                         symbol:@"sparkles"
                          color:[NSColor systemTealColor]];
    [self addFullWidthView:self.previewButton toStack:previewSection];

    NSButton *resetCollision = [self actionButtonWithTitle:@"Reset particle settings"
                                                   symbol:@"arrow.counterclockwise"
                                                  tooltip:@"Restore the default collision effect configuration"
                                                   action:@selector(resetCollisionOptions:)];
    resetCollision.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    [self addFullWidthView:resetCollision toStack:previewSection];
    [self addSection:previewSection toPane:pane];

    LHCPanelView *noteCard = [[LHCPanelView alloc] initWithFrame:NSZeroRect];
    noteCard.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *note = [self wrappingLabelWithString:@"Particle count is multiplied by the selected event preset. The collision sequence uses two incoming bunches, an additive SceneKit particle shower, track segments, shock-wave rings and a brief light flash."
                                                 font:[NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular]
                                                color:[NSColor secondaryLabelColor]];
    [noteCard addSubview:note];
    [NSLayoutConstraint activateConstraints:@[
        [note.leadingAnchor constraintEqualToAnchor:noteCard.leadingAnchor constant:13],
        [note.trailingAnchor constraintEqualToAnchor:noteCard.trailingAnchor constant:-13],
        [note.topAnchor constraintEqualToAnchor:noteCard.topAnchor constant:11],
        [note.bottomAnchor constraintEqualToAnchor:noteCard.bottomAnchor constant:-11]
    ]];
    [self addFullWidthView:noteCard toStack:pane];

    return pane;
}

- (LHCPanelView *)buildSelectionCard {
    LHCPanelView *card = [[LHCPanelView alloc] initWithFrame:NSZeroRect];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.accentColor = LHCUIColor(0.43, 0.82, 1.0);

    self.selectionCategoryLabel = [NSTextField labelWithString:@"ACCELERATOR"];
    self.selectionCategoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectionCategoryLabel.maximumNumberOfLines = 1;
    self.selectionCategoryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [card addSubview:self.selectionCategoryLabel];

    self.selectionTitleLabel = [NSTextField labelWithString:@"Large Hadron Collider"];
    self.selectionTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectionTitleLabel.font = [NSFont systemFontOfSize:16.0 weight:NSFontWeightBold];
    self.selectionTitleLabel.textColor = [NSColor labelColor];
    self.selectionTitleLabel.maximumNumberOfLines = 2;
    self.selectionTitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [card addSubview:self.selectionTitleLabel];

    NSScrollView *summaryScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    summaryScroll.translatesAutoresizingMaskIntoConstraints = NO;
    summaryScroll.drawsBackground = NO;
    summaryScroll.borderType = NSNoBorder;
    summaryScroll.hasVerticalScroller = YES;
    summaryScroll.autohidesScrollers = YES;
    summaryScroll.horizontalScrollElasticity = NSScrollElasticityNone;
    [card addSubview:summaryScroll];
    self.selectionSummaryScrollView = summaryScroll;

    NSTextView *summaryTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 260, 66)];
    summaryTextView.editable = NO;
    summaryTextView.selectable = YES;
    summaryTextView.drawsBackground = NO;
    summaryTextView.font = [NSFont systemFontOfSize:10.8 weight:NSFontWeightRegular];
    summaryTextView.textColor = [NSColor secondaryLabelColor];
    summaryTextView.textContainerInset = NSMakeSize(0, 1);
    summaryTextView.textContainer.lineFragmentPadding = 0;
    summaryTextView.horizontallyResizable = NO;
    summaryTextView.verticallyResizable = YES;
    summaryTextView.autoresizingMask = NSViewWidthSizable;
    summaryTextView.minSize = NSMakeSize(0, 0);
    summaryTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    summaryTextView.textContainer.widthTracksTextView = YES;
    summaryTextView.textContainer.containerSize = NSMakeSize(260, CGFLOAT_MAX);
    summaryScroll.documentView = summaryTextView;
    self.selectionSummaryTextView = summaryTextView;

    self.selectionFactsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    self.selectionFactsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.selectionFactsStack.alignment = NSLayoutAttributeLeading;
    self.selectionFactsStack.spacing = 2;
    self.selectionFactsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.selectionFactsStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.selectionCategoryLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.selectionCategoryLabel.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-14],
        [self.selectionCategoryLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:13],
        [self.selectionTitleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.selectionTitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [self.selectionTitleLabel.topAnchor constraintEqualToAnchor:self.selectionCategoryLabel.bottomAnchor constant:2],
        [summaryScroll.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [summaryScroll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [summaryScroll.topAnchor constraintEqualToAnchor:self.selectionTitleLabel.bottomAnchor constant:7],
        [summaryScroll.heightAnchor constraintEqualToConstant:67],
        [self.selectionFactsStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.selectionFactsStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [self.selectionFactsStack.topAnchor constraintEqualToAnchor:summaryScroll.bottomAnchor constant:7],
        [self.selectionFactsStack.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-10]
    ]];

    return card;
}

#pragma mark Inspector pane switching

- (void)inspectorTabChanged:(NSSegmentedControl *)sender {
    NSStackView *pane = self.simulationPane;
    if (sender.selectedSegment == 1) {
        pane = self.modelPane;
    } else if (sender.selectedSegment == 2) {
        pane = self.collisionPane;
    }
    [self showInspectorPane:pane scrollToTop:YES];
}

- (void)showInspectorPane:(NSStackView *)pane scrollToTop:(BOOL)scrollToTop {
    if (self.currentPane == pane) {
        return;
    }
    if (self.currentPane) {
        [self.currentPane removeFromSuperview];
    }
    self.currentPane = pane;
    if (!pane) {
        return;
    }
    pane.translatesAutoresizingMaskIntoConstraints = NO;
    [self.paneHostView addSubview:pane];
    [NSLayoutConstraint activateConstraints:@[
        [pane.leadingAnchor constraintEqualToAnchor:self.paneHostView.leadingAnchor],
        [pane.trailingAnchor constraintEqualToAnchor:self.paneHostView.trailingAnchor],
        [pane.topAnchor constraintEqualToAnchor:self.paneHostView.topAnchor],
        [pane.bottomAnchor constraintEqualToAnchor:self.paneHostView.bottomAnchor]
    ]];
    [self.view layoutSubtreeIfNeeded];
    if (scrollToTop) {
        [self.inspectorScrollView.contentView scrollToPoint:NSZeroPoint];
        [self.inspectorScrollView reflectScrolledClipView:self.inspectorScrollView.contentView];
    }
}

- (void)selectInspectorTab:(NSInteger)index {
    self.inspectorTabs.selectedSegment = index;
    NSStackView *pane = index == 1 ? self.modelPane : (index == 2 ? self.collisionPane : self.simulationPane);
    [self showInspectorPane:pane scrollToTop:YES];
}

#pragma mark Scene setup

- (void)configureSceneView {
    self.sceneView.scene = self.model.scene;
    self.sceneView.pointOfView = self.model.cameraNode;
    self.sceneView.delegate = self;
    self.sceneView.rendersContinuously = YES;
    self.sceneView.playing = YES;
    [self configureInitialCameraState];
    [self updateZoomControls];
}

- (void)configureInitialCameraState {
    SCNNode *cameraNode = self.model.cameraNode;
    if (!cameraNode) {
        return;
    }

    SCNVector3 target = self.model.cameraTarget;
    SCNVector3 initial = self.model.initialCameraPosition;
    SCNVector3 offset = SCNVector3Make(initial.x - target.x,
                                       initial.y - target.y,
                                       initial.z - target.z);
    CGFloat distance = sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z);
    if (distance < 0.001) {
        distance = LHCZoomFarDistance;
    }

    self.cameraOrbitTarget = target;
    self.cameraYaw = atan2(offset.x, offset.z);
    self.cameraPitch = asin(LHCClamp(offset.y / distance, -1.0, 1.0));
    self.cameraDistance = LHCClamp(distance, LHCZoomNearDistance, LHCZoomFarDistance);
    self.initialCameraYaw = self.cameraYaw;
    self.initialCameraPitch = self.cameraPitch;
    self.initialCameraDistance = self.cameraDistance;

    [self applyCameraState];
}

- (void)applyCameraState {
    SCNNode *cameraNode = self.model.cameraNode;
    if (!cameraNode) {
        return;
    }

    CGFloat cosPitch = cos(self.cameraPitch);
    SCNVector3 offset = SCNVector3Make(sin(self.cameraYaw) * cosPitch * self.cameraDistance,
                                       sin(self.cameraPitch) * self.cameraDistance,
                                       cos(self.cameraYaw) * cosPitch * self.cameraDistance);
    cameraNode.position = SCNVector3Make(self.cameraOrbitTarget.x + offset.x,
                                         self.cameraOrbitTarget.y + offset.y,
                                         self.cameraOrbitTarget.z + offset.z);
    [cameraNode lookAt:self.cameraOrbitTarget
                    up:SCNVector3Make(0, 1, 0)
            localFront:SCNVector3Make(0, 0, -1)];
}

- (void)updateZoomControls {
    if (!self.zoomRow) {
        return;
    }
    CGFloat span = LHCZoomFarDistance - LHCZoomNearDistance;
    CGFloat percent = span > 0.0
        ? (LHCZoomFarDistance - self.cameraDistance) / span * 100.0
        : 50.0;
    self.zoomRow.slider.doubleValue = LHCClamp(percent, 0.0, 100.0);
    [self.zoomRow refreshValueLabel];
}

- (void)handleSceneOrbitDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY {
    [self cancelCameraAnimation];
    self.cameraYaw = fmod(self.cameraYaw - deltaX * LHCCameraDragSensitivity + M_PI,
                          M_PI * 2.0) - M_PI;
    self.cameraPitch = LHCClamp(self.cameraPitch + deltaY * LHCCameraDragSensitivity,
                                LHCCameraMinimumPitch,
                                LHCCameraMaximumPitch);
    [self applyCameraState];
}

- (void)handleSceneZoomDelta:(CGFloat)delta {
    [self cancelCameraAnimation];
    CGFloat factor = exp(-delta * 0.01);
    self.cameraDistance = LHCClamp(self.cameraDistance * factor,
                                   LHCZoomNearDistance,
                                   LHCZoomFarDistance);
    [self applyCameraState];
    [self updateZoomControls];
}

#pragma mark Camera animation

- (void)cancelCameraAnimation {
    [self.cameraAnimationTimer invalidate];
    self.cameraAnimationTimer = nil;
}

- (void)animateCameraToTarget:(SCNVector3)target
                          yaw:(CGFloat)yaw
                        pitch:(CGFloat)pitch
                     distance:(CGFloat)distance
                     duration:(NSTimeInterval)duration {
    [self cancelCameraAnimation];

    CGFloat endYaw = yaw;
    while (endYaw - self.cameraYaw > M_PI) {
        endYaw -= M_PI * 2.0;
    }
    while (endYaw - self.cameraYaw < -M_PI) {
        endYaw += M_PI * 2.0;
    }

    self.cameraAnimationStartTarget = self.cameraOrbitTarget;
    self.cameraAnimationEndTarget = target;
    self.cameraAnimationStartYaw = self.cameraYaw;
    self.cameraAnimationEndYaw = endYaw;
    self.cameraAnimationStartPitch = self.cameraPitch;
    self.cameraAnimationEndPitch = LHCClamp(pitch, LHCCameraMinimumPitch, LHCCameraMaximumPitch);
    self.cameraAnimationStartDistance = self.cameraDistance;
    self.cameraAnimationEndDistance = LHCClamp(distance, LHCZoomNearDistance, LHCZoomFarDistance);

    if (duration <= 0.001) {
        self.cameraOrbitTarget = self.cameraAnimationEndTarget;
        self.cameraYaw = self.cameraAnimationEndYaw;
        self.cameraPitch = self.cameraAnimationEndPitch;
        self.cameraDistance = self.cameraAnimationEndDistance;
        [self applyCameraState];
        [self updateZoomControls];
        return;
    }

    self.cameraAnimationStartTime = CACurrentMediaTime();
    self.cameraAnimationDuration = duration;

    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 60.0
                                           repeats:YES
                                             block:^(NSTimer *theTimer) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            [theTimer invalidate];
            return;
        }
        [strongSelf stepCameraAnimation:theTimer];
    }];
    self.cameraAnimationTimer = timer;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    [self stepCameraAnimation:timer];
}

- (void)stepCameraAnimation:(NSTimer *)timer {
    NSTimeInterval elapsed = CACurrentMediaTime() - self.cameraAnimationStartTime;
    CGFloat progress = self.cameraAnimationDuration > 0.0
        ? (CGFloat)(elapsed / self.cameraAnimationDuration)
        : 1.0;
    progress = LHCClamp(progress, 0.0, 1.0);
    CGFloat eased = LHCEaseInOut(progress);

    self.cameraOrbitTarget = LHCLerpVector(self.cameraAnimationStartTarget,
                                           self.cameraAnimationEndTarget,
                                           eased);
    self.cameraYaw = self.cameraAnimationStartYaw +
        (self.cameraAnimationEndYaw - self.cameraAnimationStartYaw) * eased;
    self.cameraPitch = self.cameraAnimationStartPitch +
        (self.cameraAnimationEndPitch - self.cameraAnimationStartPitch) * eased;
    self.cameraDistance = self.cameraAnimationStartDistance +
        (self.cameraAnimationEndDistance - self.cameraAnimationStartDistance) * eased;
    [self applyCameraState];
    [self updateZoomControls];

    if (progress >= 1.0) {
        [timer invalidate];
        if (timer == self.cameraAnimationTimer) {
            self.cameraAnimationTimer = nil;
        }
    }
}

#pragma mark Initial UI synchronisation

- (void)synchronizeInspectorWithConfiguration {
    LHCSimulationConfig *config = self.configuration;

    self.beamParticleCountRow.slider.doubleValue = config.beamParticleCount;
    [self.beamParticleCountRow refreshValueLabel];
    self.speedRow.slider.doubleValue = config.beamSpeed;
    [self.speedRow refreshValueLabel];
    self.tunnelOpacityRow.slider.doubleValue = config.tunnelOpacity * 100.0;
    [self.tunnelOpacityRow refreshValueLabel];
    self.detectorScaleRow.slider.doubleValue = config.detectorScale * 100.0;
    [self.detectorScaleRow refreshValueLabel];

    self.terrainToggle.state = config.showTerrain ? NSControlStateValueOn : NSControlStateValueOff;
    self.tunnelToggle.state = config.showTunnel ? NSControlStateValueOn : NSControlStateValueOff;
    self.magnetsToggle.state = config.showMagnets ? NSControlStateValueOn : NSControlStateValueOff;
    self.detectorsToggle.state = config.showDetectors ? NSControlStateValueOn : NSControlStateValueOff;
    self.labelsToggle.state = config.showLabels ? NSControlStateValueOn : NSControlStateValueOff;
    self.cutawayToggle.state = config.cutawayView ? NSControlStateValueOn : NSControlStateValueOff;

    self.particleCountRow.slider.doubleValue = config.particleCount;
    [self.particleCountRow refreshValueLabel];
    self.particleSpreadRow.slider.doubleValue = config.particleSpread;
    [self.particleSpreadRow refreshValueLabel];
    self.particleLifetimeRow.slider.doubleValue = config.particleLifetime;
    [self.particleLifetimeRow refreshValueLabel];
    self.particleVelocityRow.slider.doubleValue = config.particleVelocity;
    [self.particleVelocityRow refreshValueLabel];
    self.particleSizeRow.slider.doubleValue = config.particleSize;
    [self.particleSizeRow refreshValueLabel];

    [self selectDetectorPopupIdentifier:config.collisionDetectorIdentifier];
    [self.presetPopup selectItemAtIndex:config.collisionPresetIndex];
    [self updateCollisionPresetUI];
    [self updateCollisionSummary];
}

- (void)selectDetectorPopupIdentifier:(NSString *)identifier {
    for (NSMenuItem *item in self.detectorPopup.itemArray) {
        if ([item.representedObject isEqualToString:identifier]) {
            [self.detectorPopup selectItem:item];
            return;
        }
    }
    [self.detectorPopup selectItemAtIndex:0];
}

- (void)refreshEnergyLabel {
    self.energyLabel.stringValue = [NSString stringWithFormat:@"%.1f TeV / beam  ·  %.1f TeV collision",
                                    self.configuration.beamEnergyTeV,
                                    self.configuration.collisionEnergyTeV];
}

- (void)updateCollisionPresetUI {
    LHCCollisionPreset *preset = self.configuration.collisionPreset;
    self.presetPopup.title = preset.name;
    [self.presetPopup selectItemAtIndex:self.configuration.collisionPresetIndex];
    self.presetEnergyLabel.stringValue = preset.energyLabel;
    self.presetDetailLabel.stringValue = preset.detail;
    NSColor *accent = preset.palette.firstObject ?: [NSColor systemTealColor];
    self.presetEnergyLabel.textColor = accent;
}

- (void)updateCollisionSummary {
    LHCCollisionPreset *preset = self.configuration.collisionPreset;
    self.collisionSummaryLabel.stringValue = [NSString stringWithFormat:@"≈ %ld particles · %lu colours · √s = %.1f TeV",
                                              (long)self.configuration.effectiveParticleCount,
                                              (unsigned long)preset.palette.count,
                                              self.configuration.collisionEnergyTeV];
    NSString *name = self.model.partCatalog[self.configuration.collisionDetectorIdentifier].name ?: @"ATLAS";
    [self updateProminentButton:self.previewButton
                          title:[NSString stringWithFormat:@"Test burst at %@", name]
                         symbol:@"sparkles"
                          color:[NSColor systemTealColor]];
}

#pragma mark Part selection

- (void)handleSceneClickAtPoint:(NSPoint)point {
    NSDictionary<SCNHitTestOption, id> *options = @{
        SCNHitTestOptionSearchMode: @(SCNHitTestSearchModeAll),
        SCNHitTestOptionBackFaceCulling: @YES
    };
    NSArray<SCNHitTestResult *> *results = [self.sceneView hitTest:point options:options];
    for (SCNHitTestResult *result in results) {
        LHCPartInfo *info = [self.model partInfoForHitNode:result.node];
        if (info) {
            SCNNode *partNode = [self partNodeForFocusFromHitNode:result.node];
            [self showPartInfo:info partNode:partNode];
            [self focusCameraOnPartInfo:info partNode:partNode hitResult:result];
            return;
        }
    }
}

- (SCNNode *)partNodeForFocusFromHitNode:(SCNNode *)node {
    SCNNode *candidate = node;
    while (candidate) {
        if ([candidate.name hasPrefix:@"part."]) {
            return candidate;
        }
        candidate = candidate.parentNode;
    }
    return node;
}

- (void)focusCameraOnPartInfo:(LHCPartInfo *)info
                     partNode:(SCNNode *)partNode
                    hitResult:(SCNHitTestResult *)hitResult {
    if (!partNode) {
        return;
    }

    // Clicking empty terrain should only reset the selection, not zoom the
    // camera into the centre of the ring.
    if ([info.identifier isEqualToString:@"overview"]) {
        return;
    }

    SCNVector3 focusPoint = SCNVector3Zero;
    CGFloat focusDistance = 14.0;

    if (info.isDetector) {
        SCNNode *detector = [self.model detectorNodeWithIdentifier:info.identifier] ?: partNode;
        SCNVector3 origin = [detector convertPosition:SCNVector3Zero toNode:nil];
        focusPoint = SCNVector3Make(origin.x, 1.35, origin.z);
        focusDistance = 15.0;
    } else if ([info.identifier isEqualToString:@"beam"] ||
               [info.identifier isEqualToString:@"vacuum"]) {
        SCNVector3 world = hitResult.worldCoordinates;
        focusPoint = SCNVector3Make(world.x, MAX(1.25, world.y), world.z);
        focusDistance = [info.identifier isEqualToString:@"beam"] ? 16.0 : 12.0;
    } else {
        focusPoint = [partNode convertPosition:SCNVector3Zero toNode:nil];
        focusDistance = [info.identifier isEqualToString:@"rf"] ? 10.0 : 8.5;
    }

    // Never zoom out while focusing; keep the current framing when the user
    // is already closer than the suggested distance.
    CGFloat targetDistance = MIN(self.cameraDistance, focusDistance);
    targetDistance = LHCClamp(targetDistance, LHCZoomNearDistance, LHCZoomFarDistance);
    [self animateCameraToTarget:focusPoint
                            yaw:self.cameraYaw
                          pitch:self.cameraPitch
                       distance:targetDistance
                       duration:0.55];
}

- (void)showPartInfo:(LHCPartInfo *)info partNode:(nullable SCNNode *)partNode {
    self.selectedPart = info;
    NSColor *accent = info.accentColor ?: [NSColor systemTealColor];

    self.selectionCategoryLabel.attributedStringValue = [[NSAttributedString alloc]
        initWithString:[info.category uppercaseString]
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:9.0 weight:NSFontWeightSemibold],
                NSForegroundColorAttributeName: accent,
                NSKernAttributeName: @0.9
            }];
    self.selectionTitleLabel.stringValue = info.name;

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 1.5;
    self.selectionSummaryTextView.textStorage.attributedString = [[NSAttributedString alloc]
        initWithString:info.summary
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:10.8 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
                NSParagraphStyleAttributeName: paragraph
            }];
    [self.selectionSummaryTextView scrollRangeToVisible:NSMakeRange(0, 0)];

    for (NSView *view in [self.selectionFactsStack.arrangedSubviews copy]) {
        [self.selectionFactsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSString *fact in info.facts) {
        NSString *line = [NSString stringWithFormat:@"•  %@", fact];
        NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc]
            initWithString:line
                attributes:@{
                    NSFontAttributeName: [NSFont systemFontOfSize:10.2 weight:NSFontWeightRegular],
                    NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
                }];
        [attributed addAttribute:NSForegroundColorAttributeName
                           value:accent
                           range:NSMakeRange(0, 1)];
        NSTextField *factLabel = [NSTextField labelWithString:@""];
        factLabel.translatesAutoresizingMaskIntoConstraints = NO;
        factLabel.attributedStringValue = attributed;
        factLabel.maximumNumberOfLines = 2;
        factLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self.selectionFactsStack addArrangedSubview:factLabel];
        [factLabel.widthAnchor constraintEqualToAnchor:self.selectionFactsStack.widthAnchor].active = YES;
    }
    self.selectionCard.accentColor = accent;
    [self.selectionCard setNeedsDisplay:YES];

    SCNNode *node = partNode;
    if (!node && info.isDetector) {
        node = [self.model detectorNodeWithIdentifier:info.identifier];
    }
    [self.model highlightNode:node accentColor:accent];

    if (info.isDetector) {
        self.configuration.collisionDetectorIdentifier = info.identifier;
        [self.configuration saveToUserDefaults];
        [self selectDetectorPopupIdentifier:info.identifier];
        [self updateCollisionSummary];
    }
}

#pragma mark Actions

- (IBAction)togglePlayPause:(id)sender {
    if (self.beamState == LHCBeamStateCirculating) {
        [self applyBeamState:LHCBeamStatePaused];
    } else if (self.beamState == LHCBeamStatePaused) {
        [self applyBeamState:LHCBeamStateCirculating];
    }
}

- (IBAction)injectBeam:(id)sender {
    if (self.beamState == LHCBeamStateInjecting || self.beamState == LHCBeamStateColliding) {
        return;
    }
    [self cleanupCollisionEffects];
    self.injectionToken += 1;
    NSInteger token = self.injectionToken;

    [self.model resetBeamPhase];
    [self.model setBeamOpacity:0.0];
    [self.model.beamGroupA runAction:[SCNAction fadeInWithDuration:0.85]];
    [self.model.beamGroupB runAction:[SCNAction fadeInWithDuration:0.85]];
    [self applyBeamState:LHCBeamStateInjecting];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || token != strongSelf.injectionToken || strongSelf.beamState != LHCBeamStateInjecting) {
            return;
        }
        [strongSelf applyBeamState:LHCBeamStateCirculating];
    });
}

- (IBAction)collideBeams:(id)sender {
    if (self.beamState != LHCBeamStateCirculating && self.beamState != LHCBeamStatePaused) {
        return;
    }

    [self cleanupCollisionEffects];
    self.collisionToken += 1;
    NSInteger token = self.collisionToken;
    self.collisionWasPaused = (self.beamState == LHCBeamStatePaused);

    NSString *detectorIdentifier = self.configuration.collisionDetectorIdentifier ?: @"atlas";
    LHCPartInfo *detectorInfo = self.model.partCatalog[detectorIdentifier];
    if (![self.model detectorNodeWithIdentifier:detectorIdentifier]) {
        detectorIdentifier = @"atlas";
        detectorInfo = self.model.partCatalog[@"atlas"];
    }
    self.configuration.collisionDetectorIdentifier = detectorIdentifier;

    SCNVector3 collisionPoint = [self.model collisionPointForDetectorIdentifier:detectorIdentifier];
    SCNVector3 tangent = [self.model beamTangentForDetectorIdentifier:detectorIdentifier];
    CGFloat travel = 2.65;
    CGFloat duration = 0.52 / MAX(0.55, self.configuration.beamSpeed);

    SCNNode *incomingA = [LHCParticleSystemFactory incomingBunchClusterWithColor:LHCUIColor(0.31, 0.92, 1.0)];
    SCNNode *incomingB = [LHCParticleSystemFactory incomingBunchClusterWithColor:LHCUIColor(1.0, 0.32, 0.82)];
    incomingA.position = SCNVector3Make(collisionPoint.x + tangent.x * travel,
                                        collisionPoint.y,
                                        collisionPoint.z + tangent.z * travel);
    incomingB.position = SCNVector3Make(collisionPoint.x - tangent.x * travel,
                                        collisionPoint.y,
                                        collisionPoint.z - tangent.z * travel);
    incomingA.eulerAngles = SCNVector3Make(0, atan2(-tangent.z, tangent.x), 0);
    incomingB.eulerAngles = SCNVector3Make(0, atan2(tangent.z, -tangent.x), 0);
    [self.model.scene.rootNode addChildNode:incomingA];
    [self.model.scene.rootNode addChildNode:incomingB];
    [self.activeCollisionNodes addObjectsFromArray:@[incomingA, incomingB]];

    SCNAction *moveA = [SCNAction moveTo:collisionPoint duration:duration];
    moveA.timingMode = SCNActionTimingModeEaseIn;
    SCNAction *moveB = [SCNAction moveTo:collisionPoint duration:duration];
    moveB.timingMode = SCNActionTimingModeEaseIn;
    [incomingA runAction:[SCNAction group:@[moveA, [SCNAction scaleTo:0.50 duration:duration]]]];
    [incomingB runAction:[SCNAction group:@[moveB, [SCNAction scaleTo:0.50 duration:duration]]]];

    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration:0.16];
    [self.model setBeamOpacity:0.18];
    [SCNTransaction commit];

    self.collisionEventSummary = [NSString stringWithFormat:@"%@  ·  ≈%ld particles  ·  √s %.1f TeV",
                                  detectorInfo.name ?: @"ATLAS",
                                  (long)self.configuration.effectiveParticleCount,
                                  self.configuration.collisionEnergyTeV];
    [self applyBeamState:LHCBeamStateColliding];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((duration + 0.01) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || token != strongSelf.collisionToken ||
            strongSelf.beamState != LHCBeamStateColliding) {
            return;
        }
        [strongSelf removeCollisionNode:incomingA];
        [strongSelf removeCollisionNode:incomingB];
        [strongSelf triggerCollisionExplosionAtPoint:collisionPoint token:token];
    });
}

- (void)triggerCollisionExplosionAtPoint:(SCNVector3)point token:(NSInteger)token {
    SCNNode *effect = [LHCParticleSystemFactory collisionEffectWithPreset:self.configuration.collisionPreset
                                                                  config:self.configuration];
    effect.position = point;
    [self.model.scene.rootNode addChildNode:effect];
    [self.activeCollisionNodes addObject:effect];
    [self flashScene];

    NSTimeInterval effectDuration = [LHCParticleSystemFactory suggestedEffectDurationForConfig:self.configuration];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((effectDuration + 0.25) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || token != strongSelf.collisionToken) {
            return;
        }
        [strongSelf removeCollisionNode:effect];
        [SCNTransaction begin];
        [SCNTransaction setAnimationDuration:0.3];
        [strongSelf.model setBeamOpacity:1.0];
        [SCNTransaction commit];
        [strongSelf applyBeamState:strongSelf.collisionWasPaused ? LHCBeamStatePaused : LHCBeamStateCirculating];
    });
}

- (IBAction)resetSimulation:(id)sender {
    self.injectionToken += 1;
    self.collisionToken += 1;
    [self cleanupCollisionEffects];

    self.configuration.beamSpeed = 1.0;
    self.configuration.beamParticleCount = 1;
    self.configuration.beamEnergyTeV = 6.8;
    [self.configuration saveToUserDefaults];
    self.beamParticleCountRow.slider.doubleValue = self.configuration.beamParticleCount;
    [self.beamParticleCountRow refreshValueLabel];
    self.speedRow.slider.doubleValue = self.configuration.beamSpeed;
    [self.speedRow refreshValueLabel];
    [self.model applyBeamParticleCount:self.configuration.beamParticleCount];
    [self refreshEnergyLabel];

    [self.model resetBeamPhase];
    [self.model setBeamOpacity:0.0];
    [self.model.beamGroupA runAction:[SCNAction fadeInWithDuration:0.65]];
    [self.model.beamGroupB runAction:[SCNAction fadeInWithDuration:0.65]];
    [self applyBeamState:LHCBeamStateInjecting];

    NSInteger token = ++self.injectionToken;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || token != strongSelf.injectionToken || strongSelf.beamState != LHCBeamStateInjecting) {
            return;
        }
        [strongSelf applyBeamState:LHCBeamStateCirculating];
    });
}

- (IBAction)resetCamera:(id)sender {
    if (!self.model.cameraNode) {
        return;
    }
    [self animateCameraToTarget:self.model.cameraTarget
                            yaw:self.initialCameraYaw
                          pitch:self.initialCameraPitch
                       distance:self.initialCameraDistance
                       duration:0.55];
}

- (void)beamParticleCountChanged:(NSSlider *)sender {
    NSInteger count = (NSInteger)llround(sender.doubleValue);
    self.configuration.beamParticleCount = count;
    [self.model applyBeamParticleCount:count];
    [self.beamParticleCountRow refreshValueLabel];
    [self.configuration saveToUserDefaults];
}

- (void)beamSpeedChanged:(NSSlider *)sender {
    self.configuration.beamSpeed = sender.doubleValue;
    [self.speedRow refreshValueLabel];
    [self.configuration saveToUserDefaults];
}

- (void)zoomChanged:(NSSlider *)sender {
    [self cancelCameraAnimation];
    CGFloat percent = LHCClamp(sender.doubleValue, 0.0, 100.0);
    self.cameraDistance = LHCZoomFarDistance -
        (percent / 100.0) * (LHCZoomFarDistance - LHCZoomNearDistance);
    [self applyCameraState];
    [self.zoomRow refreshValueLabel];
}

- (void)tunnelOpacityChanged:(NSSlider *)sender {
    self.configuration.tunnelOpacity = sender.doubleValue / 100.0;
    [self.tunnelOpacityRow refreshValueLabel];
    [self.model applyModelConfiguration:self.configuration];
    [self.configuration saveToUserDefaults];
}

- (void)detectorScaleChanged:(NSSlider *)sender {
    self.configuration.detectorScale = sender.doubleValue / 100.0;
    [self.detectorScaleRow refreshValueLabel];
    [self.model applyModelConfiguration:self.configuration];
    [self.configuration saveToUserDefaults];
}

- (void)modelOptionChanged:(NSButton *)sender {
    self.configuration.showTerrain = self.terrainToggle.state == NSControlStateValueOn;
    self.configuration.showTunnel = self.tunnelToggle.state == NSControlStateValueOn;
    self.configuration.showMagnets = self.magnetsToggle.state == NSControlStateValueOn;
    self.configuration.showDetectors = self.detectorsToggle.state == NSControlStateValueOn;
    self.configuration.showLabels = self.labelsToggle.state == NSControlStateValueOn;
    self.configuration.cutawayView = self.cutawayToggle.state == NSControlStateValueOn;
    [self.model applyModelConfiguration:self.configuration];
    [self.configuration saveToUserDefaults];

    if (self.configuration.showDetectors && self.configuration.showLabels && self.selectedPart.isDetector) {
        [self.model highlightPartWithIdentifier:self.selectedPart.identifier
                                    accentColor:self.selectedPart.accentColor];
    }
}

- (void)resetModelOptions:(id)sender {
    [self.configuration resetModelOptions];
    [self synchronizeInspectorWithConfiguration];
    [self.model applyModelConfiguration:self.configuration];
    if (self.selectedPart.isDetector && self.configuration.showDetectors) {
        [self.model highlightPartWithIdentifier:self.selectedPart.identifier
                                    accentColor:self.selectedPart.accentColor];
    }
}

- (void)collisionTargetChanged:(NSPopUpButton *)sender {
    NSString *identifier = sender.selectedItem.representedObject ?: @"atlas";
    self.configuration.collisionDetectorIdentifier = identifier;
    [self.configuration saveToUserDefaults];
    [self updateCollisionSummary];
}

- (void)collisionPresetChanged:(NSPopUpButton *)sender {
    self.configuration.collisionPresetIndex = sender.indexOfSelectedItem;
    [self.configuration saveToUserDefaults];
    [self updateCollisionPresetUI];
    [self updateCollisionSummary];
}

- (void)particleSettingsChanged:(NSSlider *)sender {
    self.configuration.particleCount = llround(self.particleCountRow.slider.doubleValue);
    self.configuration.particleSpread = self.particleSpreadRow.slider.doubleValue;
    self.configuration.particleLifetime = self.particleLifetimeRow.slider.doubleValue;
    self.configuration.particleVelocity = self.particleVelocityRow.slider.doubleValue;
    self.configuration.particleSize = self.particleSizeRow.slider.doubleValue;

    [self.particleCountRow refreshValueLabel];
    [self.particleSpreadRow refreshValueLabel];
    [self.particleLifetimeRow refreshValueLabel];
    [self.particleVelocityRow refreshValueLabel];
    [self.particleSizeRow refreshValueLabel];
    [self updateCollisionSummary];
    [self.configuration saveToUserDefaults];
}

- (void)resetCollisionOptions:(id)sender {
    [self.configuration resetCollisionOptions];
    self.particleCountRow.slider.doubleValue = self.configuration.particleCount;
    self.particleSpreadRow.slider.doubleValue = self.configuration.particleSpread;
    self.particleLifetimeRow.slider.doubleValue = self.configuration.particleLifetime;
    self.particleVelocityRow.slider.doubleValue = self.configuration.particleVelocity;
    self.particleSizeRow.slider.doubleValue = self.configuration.particleSize;
    [self.particleCountRow refreshValueLabel];
    [self.particleSpreadRow refreshValueLabel];
    [self.particleLifetimeRow refreshValueLabel];
    [self.particleVelocityRow refreshValueLabel];
    [self.particleSizeRow refreshValueLabel];
    [self.presetPopup selectItemAtIndex:self.configuration.collisionPresetIndex];
    [self updateCollisionPresetUI];
    [self updateCollisionSummary];
}

#pragma mark Beam state

- (void)applyBeamState:(LHCBeamState)state {
    self.beamState = state;
    NSColor *dotColor;
    NSString *status = @"Circulating";
    NSString *detail = @"Two counter-rotating beams";
    NSString *playTitle = @"Pause Beams";
    NSString *playSymbol = @"pause.fill";

    switch (state) {
        case LHCBeamStateIdle:
            dotColor = [NSColor systemGrayColor];
            status = @"Standby";
            detail = @"Beam animation is idle";
            playTitle = @"Start Beams";
            playSymbol = @"play.fill";
            break;
        case LHCBeamStateInjecting:
            dotColor = [NSColor systemBlueColor];
            status = @"Injecting beam";
            detail = @"Ramping proton bunches into the ring";
            playTitle = @"Injecting…";
            playSymbol = @"arrow.down.circle.fill";
            break;
        case LHCBeamStateCirculating:
            dotColor = [NSColor systemGreenColor];
            status = @"Circulating";
            detail = [NSString stringWithFormat:@"Cyan + magenta beams · %.1f TeV each", self.configuration.beamEnergyTeV];
            playTitle = @"Pause Beams";
            playSymbol = @"pause.fill";
            break;
        case LHCBeamStatePaused:
            dotColor = [NSColor systemOrangeColor];
            status = @"Beams paused";
            detail = @"Orbit held at the current phase";
            playTitle = @"Resume Beams";
            playSymbol = @"play.fill";
            break;
        case LHCBeamStateColliding:
            dotColor = [NSColor systemPinkColor];
            status = @"Collision event";
            detail = self.collisionEventSummary.length > 0
                ? self.collisionEventSummary
                : @"Beams brought into collision";
            playTitle = @"Collision";
            playSymbol = @"bolt.fill";
            break;
        default:
            dotColor = [NSColor systemGreenColor];
            break;
    }

    self.statusLabel.stringValue = status;
    self.statusDetailLabel.stringValue = detail;
    self.statusDot.layer.backgroundColor = dotColor.CGColor;
    self.statusCard.accentColor = dotColor;
    [self.statusCard setNeedsDisplay:YES];

    [self updateProminentButton:self.playPauseButton title:playTitle symbol:playSymbol color:[NSColor controlAccentColor]];
    self.playPauseButton.enabled = (state == LHCBeamStateCirculating || state == LHCBeamStatePaused ||
                                    state == LHCBeamStateIdle);
    self.injectButton.enabled = (state == LHCBeamStateCirculating || state == LHCBeamStatePaused ||
                                 state == LHCBeamStateIdle);
    self.collideButton.enabled = (state == LHCBeamStateCirculating || state == LHCBeamStatePaused);
    self.previewButton.enabled = (state == LHCBeamStateCirculating || state == LHCBeamStatePaused);
    [self refreshEnergyLabel];
}

#pragma mark Collision helpers

- (void)cleanupCollisionEffects {
    for (SCNNode *node in [self.activeCollisionNodes copy]) {
        [node removeAllActions];
        [node removeFromParentNode];
    }
    [self.activeCollisionNodes removeAllObjects];
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration:0.2];
    [self.model setBeamOpacity:1.0];
    [SCNTransaction commit];
}

- (void)removeCollisionNode:(SCNNode *)node {
    if (!node) {
        return;
    }
    [node removeAllActions];
    [node removeFromParentNode];
    [self.activeCollisionNodes removeObjectIdenticalTo:node];
}

- (void)flashScene {
    if (!self.collisionFlashView) {
        return;
    }
    self.collisionFlashView.hidden = NO;
    self.collisionFlashView.alphaValue = 0.0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.055;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.collisionFlashView.animator.alphaValue = 0.34;
    } completionHandler:^{
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.34;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            self.collisionFlashView.animator.alphaValue = 0.0;
        } completionHandler:^{
            self.collisionFlashView.hidden = YES;
        }];
    }];
}

#pragma mark SCNSceneRendererDelegate

- (void)renderer:(id<SCNSceneRenderer>)renderer updateAtTime:(NSTimeInterval)time {
    if (self.lastRenderTime <= 0) {
        self.lastRenderTime = time;
        return;
    }
    NSTimeInterval delta = time - self.lastRenderTime;
    self.lastRenderTime = time;
    if (delta <= 0 || delta > 0.2) {
        return;
    }
    if (self.beamState != LHCBeamStateCirculating && self.beamState != LHCBeamStateInjecting) {
        return;
    }
    CGFloat injectionFactor = self.beamState == LHCBeamStateInjecting ? 0.30 : 1.0;
    CGFloat angularSpeed = 0.52 * self.configuration.beamSpeed * injectionFactor;
    [self.model advanceBeamsByRadians:(CGFloat)delta * angularSpeed];
}

#pragma mark NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return 302.0;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return MIN(410.0, NSWidth(splitView.bounds) - 620.0);
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
    return NO;
}

@end
