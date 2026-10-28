#import <UIKit/UIKit.h>

@interface RBFloating : NSObject

+ (instancetype)shared;
- (void)show;
- (void)hide;
- (void)hideTemporarily;
- (void)restoreForForeground;
- (void)sceneDidDeactivate:(UIScene *)scene;
- (void)applyPrefs;          /* size / opacity changed */
- (void)refreshVisibility;   /* re-evaluate the per-app switch */
- (void)updatePosition:(CGPoint)point fromWindow:(UIWindow *)sourceWindow;

@end
