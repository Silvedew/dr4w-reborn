#import <UIKit/UIKit.h>

@interface RBManager : NSObject

+ (instancetype)shared;

- (BOOL)isShowing;
- (void)toggle;
- (void)present;
- (void)dismiss;

@end
