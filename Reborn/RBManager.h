#import <UIKit/UIKit.h>

BOOL RBIsSpringBoard(void);

@interface RBManager : NSObject

+ (instancetype)shared;

- (BOOL)isShowing;
- (void)toggle;
- (void)present;
- (void)dismiss;

@end
