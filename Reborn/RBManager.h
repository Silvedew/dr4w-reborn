#import <UIKit/UIKit.h>
#import "RBScreenshotPolicy.h"
@class RBController;

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
- (BOOL)isActiveDrawingController:(RBController *)controller;
- (void)requestScreenshotForController:(RBController *)controller deadline:(NSTimeInterval)deadline
                             willSend:(BOOL (^)(void))willSend
                           completion:(void (^)(RBScreenshotResult))completion;

@end
