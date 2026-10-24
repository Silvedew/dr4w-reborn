#pragma once
#import <UIKit/UIKit.h>

@interface RBBrushPopover : UIViewController
- (instancetype)initWithColor:(UIColor *)color width:(CGFloat)width
    colorChange:(void (^)(UIColor *))colorChange widthChange:(void (^)(CGFloat))widthChange
    widthCommit:(void (^)(CGFloat))widthCommit;
@end
