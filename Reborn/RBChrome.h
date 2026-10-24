#pragma once
#import <UIKit/UIKit.h>

// A single material layer, with a solid equivalent for accessibility settings.
@interface RBChromeSurface : UIView
- (instancetype)initWithFrame:(CGRect)frame usesMaterial:(BOOL)usesMaterial;
@end

// Native touch cancellation, immediate press feedback, and interruptible release.
@interface RBChromeButton : UIButton
@end
