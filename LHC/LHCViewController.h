//
//  LHCViewController.h
//  LHC Interactive
//
//  The main application view controller.  Builds the AppKit inspector,
//  hosts the SceneKit view and coordinates the live simulation.
//

#import <Cocoa/Cocoa.h>
#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LHCViewController : NSViewController

- (IBAction)togglePlayPause:(nullable id)sender;
- (IBAction)injectBeam:(nullable id)sender;
- (IBAction)collideBeams:(nullable id)sender;
- (IBAction)resetSimulation:(nullable id)sender;
- (IBAction)resetCamera:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
