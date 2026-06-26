//
//  LHCSceneView.h
//  LHC Interactive
//
//  SCNView subclass that distinguishes a click from an orbit drag and
//  forwards navigation gestures to the owning view controller.
//

#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LHCSceneView : SCNView

/// Called when the user clicks without dragging.
@property (nonatomic, copy, nullable) void (^sceneClickHandler)(NSPoint pointInView);

/// Called while dragging. Delta values are in view points.
@property (nonatomic, copy, nullable) void (^sceneOrbitHandler)(CGFloat deltaX, CGFloat deltaY);

/// Called for scroll-wheel and pinch zoom gestures. Positive values zoom in.
@property (nonatomic, copy, nullable) void (^sceneZoomHandler)(CGFloat delta);

@end

NS_ASSUME_NONNULL_END
