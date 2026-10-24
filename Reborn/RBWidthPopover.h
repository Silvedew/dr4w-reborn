#pragma once
#import <UIKit/UIKit.h>

@interface RBWidthPopover : UIViewController
- (instancetype)initWithWidth:(CGFloat)width change:(void (^)(CGFloat))change commit:(void (^)(CGFloat))commit;
@end
