//
//  AppDelegate.h
//  LHC Interactive
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTextViewDelegate>

@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong, nullable) NSWindow *helpWindow;

- (IBAction)showHelpWindow:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
