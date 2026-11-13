#import "RBWindow.h"
#import "RBSettings.h"
#import "RBPencilTouchPolicy.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

@interface RBPencilGesture : UIGestureRecognizer
@property (nonatomic, weak) UIView *drawingView;
@property (nonatomic, weak) UITouch *activeTouch;
@end

@implementation RBPencilGesture
- (instancetype)init {
    if ((self = [super initWithTarget:nil action:NULL])) {
        self.allowedTouchTypes = @[@(UITouchTypePencil)];
        self.cancelsTouchesInView = YES;
        self.delaysTouchesBegan = YES;
    }
    return self;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    if (!touch || !self.drawingView.userInteractionEnabled) { self.state = UIGestureRecognizerStateFailed; return; }
    self.activeTouch = touch;
    [self.drawingView touchesBegan:[NSSet setWithObject:touch] withEvent:event];
    self.state = UIGestureRecognizerStateBegan;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.activeTouch || ![touches containsObject:self.activeTouch]) return;
    [self.drawingView touchesMoved:[NSSet setWithObject:self.activeTouch] withEvent:event];
    self.state = UIGestureRecognizerStateChanged;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.activeTouch || ![touches containsObject:self.activeTouch]) return;
    [self.drawingView touchesEnded:[NSSet setWithObject:self.activeTouch] withEvent:event];
    self.activeTouch = nil;
    self.state = UIGestureRecognizerStateEnded;
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.activeTouch && [touches containsObject:self.activeTouch])
        [self.drawingView touchesCancelled:[NSSet setWithObject:self.activeTouch] withEvent:event];
    self.activeTouch = nil;
    self.state = UIGestureRecognizerStateCancelled;
}
@end

@implementation RBWindow {
    NSMutableArray<RBPencilGesture *> *_pencilGestures;
    NSMapTable<UIGestureRecognizer *, NSArray<NSNumber *> *> *_hostGestureTouchTypes;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (RBSettingBool(@"pencilOnly", NO) && self.drawingView &&
        (hit == self.drawingView || [hit isDescendantOfView:self.drawingView])) {
        [self excludePencilFromHostGesturesAtPoint:point event:event];
        return nil;
    }
    return hit;
}
- (void)excludePencilFromHostGesturesAtPoint:(CGPoint)point event:(UIEvent *)event {
    if (!_hostGestureTouchTypes) _hostGestureTouchTypes = [NSMapTable weakToStrongObjectsMapTable];
    NSArray<UIWindow *> *windows = self.windowScene ? self.windowScene.windows : UIApplication.sharedApplication.windows;
    for (UIWindow *window in windows) {
        if (window == self || window.hidden || window.windowLevel >= self.windowLevel) continue;
        CGPoint hostPoint = [self convertPoint:point toWindow:window];
        UIView *view = [window hitTest:hostPoint withEvent:event];
        for (; view; view = view.superview) {
            for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
                // The canvas recognizer must continue receiving Pencil input.
                if ([gesture isKindOfClass:RBPencilGesture.class]) continue;
                NSArray *current = gesture.allowedTouchTypes;
                NSArray *filtered = RBPencilFilteredTouchTypes(current, @(UITouchTypePencil));
                if (!filtered) continue;
                [_hostGestureTouchTypes setObject:[current copy] forKey:gesture];
                gesture.allowedTouchTypes = filtered;
            }
        }
    }
}
- (void)updatePencilRouting {
    if (!RBSettingBool(@"pencilOnly", NO) || !self.drawingView || self.hidden) {
        [self stopPencilRouting];
        return;
    }
    if (!_pencilGestures) _pencilGestures = [NSMutableArray array];
    NSArray<UIWindow *> *windows = self.windowScene ? self.windowScene.windows : UIApplication.sharedApplication.windows;
    for (UIWindow *window in windows) {
        if (window == self || window.hidden || window.windowLevel >= self.windowLevel) continue;
        BOOL found = NO;
        for (RBPencilGesture *gesture in _pencilGestures) if (gesture.view == window) { found = YES; break; }
        if (found) continue;
        RBPencilGesture *gesture = [RBPencilGesture new];
        gesture.drawingView = self.drawingView;
        [window addGestureRecognizer:gesture];
        [_pencilGestures addObject:gesture];
    }
}
- (void)stopPencilRouting {
    for (UIGestureRecognizer *gesture in _hostGestureTouchTypes) {
        NSArray *original = [_hostGestureTouchTypes objectForKey:gesture];
        if (RBPencilShouldRestoreTouchTypes(gesture.allowedTouchTypes, original, @(UITouchTypePencil)))
            gesture.allowedTouchTypes = original;
    }
    [_hostGestureTouchTypes removeAllObjects];
    for (RBPencilGesture *gesture in _pencilGestures) [gesture.view removeGestureRecognizer:gesture];
    [_pencilGestures removeAllObjects];
}
@end
