#import <UIKit/UIKit.h>

@interface RBFloating : NSObject

+ (instancetype)shared;
- (void)show;
- (void)hide;
- (void)applyPrefs;          /* size / opacity changed */
- (void)refreshVisibility;   /* re-evaluate the per-app switch */
- (void)setFrontmost:(BOOL)frontmost;

@end
