//
//  LHCSceneView.m
//  LHC Interactive
//

#import "LHCSceneView.h"

@implementation LHCSceneView {
    NSPoint _mouseDownPoint;
    NSPoint _lastDragPoint;
    BOOL _trackingClick;
}

- (void)mouseDown:(NSEvent *)event {
    _mouseDownPoint = [self convertPoint:event.locationInWindow fromView:nil];
    _lastDragPoint = _mouseDownPoint;
    _trackingClick = YES;
    [super mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint current = [self convertPoint:event.locationInWindow fromView:nil];
    if (hypot(current.x - _mouseDownPoint.x, current.y - _mouseDownPoint.y) > 4.0) {
        _trackingClick = NO;
    }

    if (self.sceneOrbitHandler) {
        CGFloat deltaX = current.x - _lastDragPoint.x;
        CGFloat deltaY = current.y - _lastDragPoint.y;
        if (fabs(deltaX) > 0.001 || fabs(deltaY) > 0.001) {
            self.sceneOrbitHandler(deltaX, deltaY);
        }
    }
    _lastDragPoint = current;
    [super mouseDragged:event];
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    BOOL isClick = _trackingClick && hypot(point.x - _mouseDownPoint.x,
                                           point.y - _mouseDownPoint.y) <= 4.0;
    [super mouseUp:event];
    _trackingClick = NO;

    if (isClick && self.sceneClickHandler) {
        self.sceneClickHandler(point);
    }
}

- (void)scrollWheel:(NSEvent *)event {
    CGFloat delta = event.scrollingDeltaY;
    if (!event.hasPreciseScrollingDeltas) {
        delta *= 10.0;
    }
    if (fabs(delta) > 0.001 && self.sceneZoomHandler) {
        self.sceneZoomHandler(delta);
    }
}

- (void)magnifyWithEvent:(NSEvent *)event {
    if (self.sceneZoomHandler && fabs(event.magnification) > 0.0001) {
        self.sceneZoomHandler(event.magnification * 100.0);
    }
}

// Let clicks work even when the cursor is over an overlay-free scene.
- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:NSCursor.openHandCursor];
}

@end
