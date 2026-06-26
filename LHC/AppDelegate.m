//
//  AppDelegate.m
//  LHC Interactive
//

#import "AppDelegate.h"
#import "LHCViewController.h"
#import <objc/message.h>

@interface AppDelegate ()
@property (nonatomic, strong, nullable) NSTextView *helpTextView;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildMainMenu];

    LHCViewController *viewController = [[LHCViewController alloc] initWithNibName:nil bundle:nil];
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1420, 900)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"LHC Interactive — Large Hadron Collider";
    window.minSize = NSMakeSize(1120, 740);
    window.contentViewController = viewController;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    window.backgroundColor = [NSColor blackColor];
    window.releasedWhenClosed = NO;
    [window setFrameAutosaveName:@"LHCInteractiveMainWindow"];

    NSScreen *screen = [NSScreen mainScreen];
    NSRect visible = screen ? screen.visibleFrame : NSMakeRect(0, 0, 1440, 900);
    CGFloat targetWidth = MIN(1420.0, NSWidth(visible) - 48.0);
    CGFloat targetHeight = MIN(900.0, NSHeight(visible) - 48.0);
    targetWidth = MAX(targetWidth, 1120.0);
    targetHeight = MAX(targetHeight, 740.0);
    [window setContentSize:NSMakeSize(targetWidth, targetHeight)];
    [window center];

    self.window = window;
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

#if DEBUG
    const char *capturePath = getenv("LHC_CAPTURE_PATH");
    if (capturePath) {
        NSString *path = [NSString stringWithUTF8String:capturePath];

        // Capture at the documented 1420x900 content size even when the
        // current display is shorter. The scene and UI are rendered into
        // bitmaps, so the window itself may extend beyond the display.
        [window setContentSize:NSMakeSize(1420, 900)];

        const char *zoomValue = getenv("LHC_CAPTURE_ZOOM");
        const char *focusValue = getenv("LHC_CAPTURE_FOCUS");
        BOOL center = getenv("LHC_CAPTURE_CENTER") != NULL;
        BOOL stressCenter = getenv("LHC_CAPTURE_STRESS_CENTER") != NULL;
        BOOL preview = getenv("LHC_CAPTURE_PREVIEW") != NULL;
        const char *orbitValue = getenv("LHC_CAPTURE_ORBIT");
        const char *scrollValue = getenv("LHC_CAPTURE_SCROLL");
        const char *delayValue = getenv("LHC_CAPTURE_DELAY");
        NSTimeInterval snapshotDelay = delayValue ? atof(delayValue) : 2.0;

        if (getenv("LHC_CAPTURE_COLLIDE")) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [viewController collideBeams:nil];
            });
        }

        // Exercise the real UI actions before taking the screenshot. This
        // leaves enough time for the camera animation to settle.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (zoomValue) {
                SEL zoomSelector = NSSelectorFromString(@"debugSetZoomPercent:");
                if ([viewController respondsToSelector:zoomSelector]) {
                    ((void (*)(id, SEL, double))objc_msgSend)(viewController,
                                                              zoomSelector,
                                                              atof(zoomValue));
                }
            }
            if (focusValue) {
                SEL focusSelector = NSSelectorFromString(@"debugFocusPartWithIdentifier:");
                if ([viewController respondsToSelector:focusSelector]) {
                    ((void (*)(id, SEL, NSString *))objc_msgSend)(
                        viewController,
                        focusSelector,
                        [NSString stringWithUTF8String:focusValue]);
                }
            }
            if (orbitValue) {
                NSArray<NSString *> *values = [[NSString stringWithUTF8String:orbitValue]
                    componentsSeparatedByString:@","];
                if (values.count >= 2) {
                    SEL orbitSelector = NSSelectorFromString(@"debugApplyOrbitDeltaX:deltaY:");
                    if ([viewController respondsToSelector:orbitSelector]) {
                        ((void (*)(id, SEL, double, double))objc_msgSend)(
                            viewController,
                            orbitSelector,
                            values[0].doubleValue,
                            values[1].doubleValue);
                    }
                }
            }
            if (scrollValue) {
                SEL scrollSelector = NSSelectorFromString(@"debugApplyScrollZoomDelta:");
                if ([viewController respondsToSelector:scrollSelector]) {
                    ((void (*)(id, SEL, double))objc_msgSend)(viewController,
                                                              scrollSelector,
                                                              atof(scrollValue));
                }
            }
            if (center) {
                SEL centerSelector = NSSelectorFromString(@"debugPerformCenterClick");
                if ([viewController respondsToSelector:centerSelector]) {
                    ((void (*)(id, SEL))objc_msgSend)(viewController, centerSelector);
                }
            }
            if (stressCenter) {
                SEL stressSelector = NSSelectorFromString(@"debugStressCenterClicks");
                if ([viewController respondsToSelector:stressSelector]) {
                    ((void (*)(id, SEL))objc_msgSend)(viewController, stressSelector);
                }
            }
            if (preview) {
                SEL previewSelector = NSSelectorFromString(@"debugPerformPreviewClick");
                if ([viewController respondsToSelector:previewSelector]) {
                    ((void (*)(id, SEL))objc_msgSend)(viewController, previewSelector);
                }
            }
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(snapshotDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [NSApp activateIgnoringOtherApps:YES];
            [self.window makeKeyAndOrderFront:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                SEL selector = NSSelectorFromString(@"writeDebugSnapshotToPath:");
                if ([viewController respondsToSelector:selector]) {
                    ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(viewController, selector, path);
                }
                void (^finish)(void) = ^{
                    if (getenv("LHC_CAPTURE_HELP")) {
                        if (getenv("LHC_CAPTURE_HELP_KEY")) {
                            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                                             location:NSZeroPoint
                                                        modifierFlags:(NSEventModifierFlagCommand |
                                                                       NSEventModifierFlagShift)
                                                            timestamp:[NSProcessInfo processInfo].systemUptime
                                                         windowNumber:self.window.windowNumber
                                                              context:nil
                                                           characters:@"?"
                                          charactersIgnoringModifiers:@"?"
                                                            isARepeat:NO
                                                              keyCode:44];
                            BOOL handled = [[NSApp mainMenu] performKeyEquivalent:event];
                            NSLog(@"LHC debug help shortcut: handled=%@ visible=%@",
                                  @(handled), @(self.helpWindow.visible));
                        }
                        if (!self.helpWindow.visible) {
                            [self showHelpWindow:nil];
                        }
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                            if (getenv("LHC_CAPTURE_HELP_SCROLL") && self.helpTextView) {
                                [self.helpTextView scrollRangeToVisible:
                                    NSMakeRange(self.helpTextView.string.length, 0)];
                            }
                            NSLog(@"LHC debug help: text=%@ visible=%@",
                                  NSStringFromRect(self.helpTextView.frame),
                                  NSStringFromRect(self.helpTextView.visibleRect));
                            NSWindow *helpWindow = self.helpWindow;
                            if (helpWindow) {
                                CGImageRef image = CGWindowListCreateImage(
                                    CGRectNull,
                                    kCGWindowListOptionIncludingWindow,
                                    (CGWindowID)helpWindow.windowNumber,
                                    kCGWindowImageBoundsIgnoreFraming);
                                if (image) {
                                    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
                                    NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG
                                                                     properties:@{}];
                                    [data writeToFile:[path stringByAppendingString:@"-help.png"]
                                           atomically:YES];
                                    CGImageRelease(image);
                                }
                            }
                            [NSApp terminate:nil];
                        });
                    } else {
                        [NSApp terminate:nil];
                    }
                };
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), finish);
            });
        });
    }
#endif
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

#pragma mark - Menu

- (void)buildMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main Menu"];
    NSApp.mainMenu = mainMenu;

    // Application menu
    NSMenuItem *applicationItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:applicationItem];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"LHC Interactive"];
    applicationItem.submenu = applicationMenu;

    NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"About LHC Interactive"
                                                   action:@selector(showAboutPanel:)
                                            keyEquivalent:@""];
    about.target = self;
    [applicationMenu addItem:about];
    [applicationMenu addItem:[NSMenuItem separatorItem]];

    [applicationMenu addItem:[self menuItemWithTitle:@"Hide LHC Interactive"
                                              action:@selector(hide:)
                                       keyEquivalent:@"h"
                                               target:nil]];
    [applicationMenu addItem:[self menuItemWithTitle:@"Hide Others"
                                              action:@selector(hideOtherApplications:)
                                       keyEquivalent:@"h"
                                               target:nil
                                   modifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)]];
    [applicationMenu addItem:[self menuItemWithTitle:@"Show All"
                                              action:@selector(unhideAllApplications:)
                                       keyEquivalent:@""
                                               target:nil]];
    [applicationMenu addItem:[NSMenuItem separatorItem]];
    [applicationMenu addItem:[self menuItemWithTitle:@"Quit LHC Interactive"
                                              action:@selector(terminate:)
                                       keyEquivalent:@"q"
                                               target:nil]];

    // Edit menu, useful for copying text from the inspector.
    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    editItem.submenu = editMenu;
    [editMenu addItem:[self menuItemWithTitle:@"Undo" action:NSSelectorFromString(@"undo:") keyEquivalent:@"z" target:nil]];
    [editMenu addItem:[self menuItemWithTitle:@"Redo" action:NSSelectorFromString(@"redo:") keyEquivalent:@"Z" target:nil]];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItem:[self menuItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x" target:nil]];
    [editMenu addItem:[self menuItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c" target:nil]];
    [editMenu addItem:[self menuItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v" target:nil]];
    [editMenu addItem:[self menuItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a" target:nil]];

    // Simulation menu; targets remain nil so the actions travel the responder chain.
    NSMenuItem *simulationItem = [[NSMenuItem alloc] initWithTitle:@"Simulation" action:nil keyEquivalent:@""];
    [mainMenu addItem:simulationItem];
    NSMenu *simulationMenu = [[NSMenu alloc] initWithTitle:@"Simulation"];
    simulationItem.submenu = simulationMenu;

    NSMenuItem *play = [self menuItemWithTitle:@"Play / Pause Beams"
                                       action:@selector(togglePlayPause:)
                                keyEquivalent:@" "
                                        target:nil
                                    modifierMask:0];
    [simulationMenu addItem:play];
    [simulationMenu addItem:[self menuItemWithTitle:@"Inject Beam"
                                             action:@selector(injectBeam:)
                                      keyEquivalent:@"i"
                                              target:nil]];
    [simulationMenu addItem:[self menuItemWithTitle:@"Collide Beams"
                                             action:@selector(collideBeams:)
                                      keyEquivalent:@"c"
                                              target:nil
                                          modifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)]];
    [simulationMenu addItem:[NSMenuItem separatorItem]];
    [simulationMenu addItem:[self menuItemWithTitle:@"Reset Simulation"
                                             action:@selector(resetSimulation:)
                                      keyEquivalent:@"r"
                                              target:nil]];
    [simulationMenu addItem:[self menuItemWithTitle:@"Center View"
                                             action:@selector(resetCamera:)
                                      keyEquivalent:@"0"
                                              target:nil]];

    // View menu
    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    [mainMenu addItem:viewItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    viewItem.submenu = viewMenu;
    [viewMenu addItem:[self menuItemWithTitle:@"Enter Full Screen"
                                       action:@selector(toggleFullScreen:)
                                keyEquivalent:@"f"
                                        target:nil
                                    modifierMask:(NSEventModifierFlagControl | NSEventModifierFlagCommand)]];

    // Window menu
    NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    [mainMenu addItem:windowItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    windowItem.submenu = windowMenu;
    [windowMenu addItem:[self menuItemWithTitle:@"Minimize"
                                         action:@selector(performMiniaturize:)
                                  keyEquivalent:@"m"
                                          target:nil]];
    [windowMenu addItem:[self menuItemWithTitle:@"Zoom"
                                         action:@selector(performZoom:)
                                  keyEquivalent:@"" target:nil]];
    NSApp.windowsMenu = windowMenu;

    // Help menu
    NSMenuItem *helpItem = [[NSMenuItem alloc] initWithTitle:@"Help" action:nil keyEquivalent:@""];
    [mainMenu addItem:helpItem];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    helpItem.submenu = helpMenu;
    NSMenuItem *help = [self menuItemWithTitle:@"LHC Interactive Help"
                                        action:@selector(showHelpWindow:)
                                 keyEquivalent:@"?"
                                         target:self];
    [helpMenu addItem:help];
    [helpMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *cern = [[NSMenuItem alloc] initWithTitle:@"CERN — The Large Hadron Collider"
                                                   action:@selector(openCERNWebsite:)
                                            keyEquivalent:@""];
    cern.target = self;
    [helpMenu addItem:cern];
    NSApp.helpMenu = helpMenu;
}

- (NSMenuItem *)menuItemWithTitle:(NSString *)title
                           action:(SEL)action
                    keyEquivalent:(NSString *)keyEquivalent
                            target:(id)target {
    return [self menuItemWithTitle:title
                            action:action
                     keyEquivalent:keyEquivalent
                             target:target
                       modifierMask:NSEventModifierFlagCommand];
}

- (NSMenuItem *)menuItemWithTitle:(NSString *)title
                           action:(SEL)action
                    keyEquivalent:(NSString *)keyEquivalent
                            target:(id)target
                      modifierMask:(NSEventModifierFlags)modifierMask {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:keyEquivalent];
    item.target = target;
    item.keyEquivalentModifierMask = modifierMask;
    return item;
}

#pragma mark - About / Help

- (void)showAboutPanel:(id)sender {
    NSAttributedString *credits = [[NSAttributedString alloc]
        initWithString:@"An interactive, fully procedural visualisation of the Large Hadron Collider.\n\n"
                         "Built with Objective-C, AppKit and SceneKit. Educational model only; "
                         "not affiliated with CERN. Detector reference: papercraft instructions by "
                         "Nathan Readioff, University of Liverpool, sourced from CERN."
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:11.0],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
            }];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{
        NSAboutPanelOptionApplicationName: @"LHC Interactive",
        NSAboutPanelOptionApplicationVersion: @"1.0",
        NSAboutPanelOptionCredits: credits
    }];
}

- (IBAction)showHelpWindow:(id)sender {
    if (!self.helpWindow) {
        [self buildHelpWindow];
    }
    [self.helpWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)closeHelpWindow:(id)sender {
    [self.helpWindow orderOut:nil];
}

- (void)buildHelpWindow {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 780, 680)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"LHC Interactive Help";
    window.minSize = NSMakeSize(640, 500);
    window.backgroundColor = [NSColor windowBackgroundColor];
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    window.releasedWhenClosed = NO;
    [window center];

    NSView *content = window.contentView;

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = NSApp.applicationIconImage;
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    icon.wantsLayer = YES;
    icon.layer.cornerRadius = 11.0;
    icon.layer.masksToBounds = YES;
    [content addSubview:icon];

    NSTextField *title = [NSTextField labelWithString:@"LHC Interactive Help"];
    title.font = [NSFont systemFontOfSize:23.0 weight:NSFontWeightBold];
    title.textColor = [NSColor labelColor];

    NSTextField *subtitle = [NSTextField labelWithString:@"Explore the Large Hadron Collider"]; 
    subtitle.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    subtitle.textColor = [NSColor secondaryLabelColor];

    NSStackView *titleStack = [NSStackView stackViewWithViews:@[title, subtitle]];
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = 2;
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:titleStack];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.boxType = NSBoxSeparator;
    [content addSubview:separator];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.scrollerStyle = NSScrollerStyleOverlay;
    [content addSubview:scrollView];

    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 700, 600)];
    textView.editable = NO;
    textView.selectable = YES;
    textView.richText = YES;
    textView.drawsBackground = NO;
    textView.textContainerInset = NSMakeSize(0, 7);
    textView.textContainer.widthTracksTextView = YES;
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.autoresizingMask = NSViewWidthSizable;
    textView.minSize = NSMakeSize(0, 0);
    textView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    textView.delegate = self;
    textView.linkTextAttributes = @{
        NSForegroundColorAttributeName: [NSColor linkColor],
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)
    };
    [textView.textStorage setAttributedString:[self helpContent]];
    [textView setSelectedRange:NSMakeRange(0, 0)];
    scrollView.documentView = textView;
    self.helpTextView = textView;

    NSTextField *version = [NSTextField labelWithString:@"LHC Interactive 1.0  ·  Educational model, not affiliated with CERN"]; 
    version.translatesAutoresizingMaskIntoConstraints = NO;
    version.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular];
    version.textColor = [NSColor tertiaryLabelColor];
    version.lineBreakMode = NSLineBreakByTruncatingTail;
    [content addSubview:version];

    NSButton *cernButton = [NSButton buttonWithTitle:@"Open CERN Website"
                                              target:self
                                              action:@selector(openCERNWebsite:)];
    cernButton.translatesAutoresizingMaskIntoConstraints = NO;
    cernButton.bezelStyle = NSBezelStyleRounded;
    cernButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    [content addSubview:cernButton];

    NSButton *closeButton = [NSButton buttonWithTitle:@"Close"
                                               target:self
                                               action:@selector(closeHelpWindow:)];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    closeButton.bezelStyle = NSBezelStyleRounded;
    closeButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    closeButton.keyEquivalent = @"\e";
    closeButton.keyEquivalentModifierMask = 0;
    [content addSubview:closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26],
        [icon.topAnchor constraintEqualToAnchor:content.topAnchor constant:22],
        [icon.widthAnchor constraintEqualToConstant:52],
        [icon.heightAnchor constraintEqualToConstant:52],

        [titleStack.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],
        [titleStack.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor],
        [titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-26],

        [separator.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26],
        [separator.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-26],
        [separator.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:18],
        [separator.heightAnchor constraintEqualToConstant:1],

        [scrollView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26],
        [scrollView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-26],
        [scrollView.topAnchor constraintEqualToAnchor:separator.bottomAnchor constant:14],
        [scrollView.bottomAnchor constraintEqualToAnchor:version.topAnchor constant:-14],

        [version.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26],
        [version.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
        [version.trailingAnchor constraintLessThanOrEqualToAnchor:cernButton.leadingAnchor constant:-14],
        [version.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-18],

        [closeButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [closeButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],
        [closeButton.widthAnchor constraintGreaterThanOrEqualToConstant:84],
        [closeButton.heightAnchor constraintEqualToConstant:30],

        [cernButton.trailingAnchor constraintEqualToAnchor:closeButton.leadingAnchor constant:-10],
        [cernButton.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
        [cernButton.heightAnchor constraintEqualToConstant:30]
    ]];

    self.helpWindow = window;
}

- (NSAttributedString *)helpContent {
    NSMutableAttributedString *content = [[NSMutableAttributedString alloc] init];

    NSMutableParagraphStyle *headingStyle = [[NSMutableParagraphStyle alloc] init];
    headingStyle.paragraphSpacingBefore = 15.0;
    headingStyle.paragraphSpacing = 6.0;

    NSMutableParagraphStyle *bodyStyle = [[NSMutableParagraphStyle alloc] init];
    bodyStyle.lineSpacing = 2.0;
    bodyStyle.paragraphSpacing = 8.0;

    NSMutableParagraphStyle *bulletStyle = [[NSMutableParagraphStyle alloc] init];
    bulletStyle.lineSpacing = 2.0;
    bulletStyle.paragraphSpacing = 5.0;
    bulletStyle.firstLineHeadIndent = 4.0;
    bulletStyle.headIndent = 16.0;

    NSMutableParagraphStyle *shortcutStyle = [[NSMutableParagraphStyle alloc] init];
    shortcutStyle.lineSpacing = 2.0;
    shortcutStyle.paragraphSpacing = 4.0;
    shortcutStyle.headIndent = 92.0;
    shortcutStyle.firstLineHeadIndent = 0.0;
    shortcutStyle.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft
                                                              location:92.0
                                                               options:@{}]];

    NSDictionary *headingAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSParagraphStyleAttributeName: headingStyle
    };
    NSDictionary *bodyAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSParagraphStyleAttributeName: bodyStyle
    };
    NSDictionary *secondaryAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
        NSParagraphStyleAttributeName: bodyStyle
    };
    NSDictionary *bulletAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSParagraphStyleAttributeName: bulletStyle
    };

    void (^appendHeading)(NSString *) = ^(NSString *text) {
        [content appendAttributedString:[[NSAttributedString alloc]
            initWithString:[text stringByAppendingString:@"\n"]
                attributes:headingAttributes]];
    };
    void (^appendBody)(NSString *) = ^(NSString *text) {
        [content appendAttributedString:[[NSAttributedString alloc]
            initWithString:[text stringByAppendingString:@"\n"]
                attributes:bodyAttributes]];
    };
    void (^appendSecondary)(NSString *) = ^(NSString *text) {
        [content appendAttributedString:[[NSAttributedString alloc]
            initWithString:[text stringByAppendingString:@"\n"]
                attributes:secondaryAttributes]];
    };
    void (^appendBullet)(NSString *) = ^(NSString *text) {
        NSString *line = [@"•  " stringByAppendingString:text];
        [content appendAttributedString:[[NSAttributedString alloc]
            initWithString:[line stringByAppendingString:@"\n"]
                attributes:bulletAttributes]];
    };
    void (^appendShortcut)(NSString *, NSString *) = ^(NSString *shortcut, NSString *description) {
        NSString *line = [NSString stringWithFormat:@"%@\t%@\n", shortcut, description];
        NSMutableAttributedString *row = [[NSMutableAttributedString alloc]
            initWithString:line
                attributes:@{
                    NSFontAttributeName: [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
                    NSForegroundColorAttributeName: [NSColor labelColor],
                    NSParagraphStyleAttributeName: shortcutStyle
                }];
        [row addAttribute:NSFontAttributeName
                    value:[NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightSemibold]
                    range:[line rangeOfString:shortcut]];
        [content appendAttributedString:row];
    };

    appendBody(@"LHC Interactive is a fully procedural, explorable model of the Large Hadron Collider. "
               "Use the 3D view and the inspector to move around the accelerator, inspect real hardware, "
               "and trigger stylised particle collisions.");

    appendHeading(@"Explore the 3D view");
    appendBullet(@"Drag in the viewport to orbit around the current focus point.");
    appendBullet(@"Scroll or pinch to zoom. The Zoom slider in the Simulate tab follows the camera position.");
    appendBullet(@"Click a detector, a coloured magnet, an RF cavity, a beam or a floating label. The inspector "
                 "updates, and the camera smoothly focuses on the component.");
    appendBullet(@"Use Center View in the top-right corner, Center View in the Simulate tab, or ⌘0 to return "
                 "to the overview.");

    appendHeading(@"Inspector tabs");
    appendBullet(@"Simulate — beam status, pause/inject/collide controls, beam speed, collision point and zoom.");
    appendBullet(@"Model — toggle terrain, tunnel, magnets, detectors and labels; adjust tunnel opacity, "
                 "detector scale and the cutaway view.");
    appendBullet(@"Collisions — choose the interaction point and event preset, tune the particle system, "
                 "and run a test burst.");
    appendSecondary(@"The selection card at the bottom of the sidebar always describes the component you last "
                    "clicked, including its role, key facts and physics context.");

    appendHeading(@"Simulation");
    appendBullet(@"Pause Beams freezes the orbiting bunches and tracers; press it again to resume.");
    appendBullet(@"Particles per beam (1–8) controls how many bright tracers with comet tails circle "
                 "in each direction; Particle speed controls their orbital velocity.");
    appendBullet(@"Inject Beam replays the injection ramp before returning to stable circulation.");
    appendBullet(@"Collide brings the beams together at the selected interaction point and runs the configured "
                 "event effect.");
    appendBullet(@"Reset restores the default beam speed, particle count and energy without changing your model or collision settings.");

    appendHeading(@"Collisions");
    appendBullet(@"Select a target with the Collision point popup or by clicking one of the four detectors.");
    appendBullet(@"Event presets change the colour palette, particle count and visual character of the shower.");
    appendBullet(@"Test burst runs the current configuration immediately at the chosen interaction point.");

    appendHeading(@"Model controls");
    appendBullet(@"Labels and detectors can be hidden independently; the inspector selection remains active.");
    appendBullet(@"Tunnel opacity and detector scale update continuously while you drag their sliders.");
    appendBullet(@"Cutaway view fades the outer detector shells so the inner tracking and calorimeter layers are visible.");

    appendHeading(@"Keyboard shortcuts");
    appendShortcut(@"Space", @"Pause or resume the beams");
    appendShortcut(@"⌘I", @"Inject a fresh beam");
    appendShortcut(@"⇧⌘C", @"Collide the beams");
    appendShortcut(@"⌘R", @"Reset the simulation");
    appendShortcut(@"⌘0", @"Center the 3D view");
    appendShortcut(@"⌘?", @"Open this help window");

    appendHeading(@"Troubleshooting");
    appendBullet(@"Xcode debugger: the shared LHC scheme disables Metal API Validation for Run. SceneKit's HDR "
                 "post-processing can otherwise stop the debugger inside the validation layer. If you enable "
                 "validation manually, the app automatically uses its LDR render path.");
    appendBullet(@"If the model appears off-screen after orbiting, click Center View or press ⌘0.");
    appendBullet(@"Appearance, simulation and collision settings are saved automatically for your user account.");
    appendSecondary(@"This is an educational, stylised reconstruction. Detector proportions and particle tracks "
                    "are simplified for clarity.");

    NSMutableAttributedString *footer = [[NSMutableAttributedString alloc]
        initWithString:@"Learn more at the CERN website."
            attributes:secondaryAttributes];
    [footer addAttribute:NSLinkAttributeName
                   value:[NSURL URLWithString:@"https://home.cern/science/accelerators/large-hadron-collider"]
                   range:NSMakeRange(0, footer.length)];
    [content appendAttributedString:footer];

    return content;
}

- (BOOL)textView:(NSTextView *)textView
    clickedOnLink:(id)link
          atIndex:(NSUInteger)charIndex {
    NSURL *url = nil;
    if ([link isKindOfClass:[NSURL class]]) {
        url = link;
    } else if ([link isKindOfClass:[NSString class]]) {
        url = [NSURL URLWithString:link];
    }
    if (!url) {
        return NO;
    }
    [[NSWorkspace sharedWorkspace] openURL:url];
    return YES;
}

- (void)openCERNWebsite:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://home.cern/science/accelerators/large-hadron-collider"];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

@end
