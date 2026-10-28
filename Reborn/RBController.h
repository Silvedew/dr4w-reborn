#import <UIKit/UIKit.h>

@interface RBController : UIViewController
- (void)previewToolbarScale:(CGFloat)scale;
- (void)commitToolbarScale:(CGFloat)scale;
- (void)refreshToolbarPreferences;
- (void)setInitialToolbarAnchor:(CGPoint)anchor fromWindow:(UIWindow *)sourceWindow;
- (void)syncFloatingPositionAfterUserClose;
- (void)cancelPendingScreenshot;
@end
