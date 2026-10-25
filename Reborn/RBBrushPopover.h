#pragma once
#import <UIKit/UIKit.h>

@interface RBBrushPopover : UIViewController
@property (nonatomic, copy) void (^closeHandler)(void);
- (instancetype)initWithColor:(UIColor *)color width:(CGFloat)width
    colorChange:(void (^)(UIColor *))colorChange widthChange:(void (^)(CGFloat))widthChange
    widthCommit:(void (^)(CGFloat))widthCommit;
- (void)updateAvailableSize:(CGSize)size;
- (void)commitPendingChanges;
@end
