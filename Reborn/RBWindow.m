#import "RBWindow.h"
#import "RBSettings.h"
#include <math.h>

@implementation RBWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!RBSettingBool(@"pencilOnly", NO) || !self.drawingView ||
        !(hit == self.drawingView || [hit isDescendantOfView:self.drawingView])) return hit;

    // A UIEvent may contain several touches; only use a touch at this hit-test point.
    UITouch *match = nil;
    for (UITouch *touch in event.allTouches) {
        CGPoint location = [touch locationInView:self];
        if (fabs(location.x - point.x) > 0.5 || fabs(location.y - point.y) > 0.5) continue;
        if (match) return nil;
        match = touch;
    }
    return match.type == UITouchTypePencil ? hit : nil;
}

@end
