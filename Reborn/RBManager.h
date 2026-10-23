#import <UIKit/UIKit.h>

BOOL RBIsSpringBoard(void);
CGRect RBHostBounds(void);
BOOL RBFrontmostIsSelf(void);

@interface RBManager : NSObject

+ (instancetype)shared;

- (BOOL)isShowing;
- (void)toggle;
- (void)present;
- (void)dismiss;
- (void)layoutForCurrentHost;

@end
