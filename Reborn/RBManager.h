#import <UIKit/UIKit.h>

BOOL RBIsSpringBoard(void);
CGRect RBHostBounds(void);

@interface RBManager : NSObject

+ (instancetype)shared;

- (BOOL)isShowing;
- (void)toggle;
- (void)present;
- (void)presentFromFloatingWindow:(UIWindow *)sourceWindow center:(CGPoint)center;
- (void)dismiss;
- (void)dismissFromUser;
- (void)layoutForCurrentHost;
- (void)applySettings;

@end
