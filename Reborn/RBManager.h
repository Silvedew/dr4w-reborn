#import <UIKit/UIKit.h>

void RBWriteLog(NSString *text);
BOOL RBIsSpringBoard(void);

@interface RBManager : NSObject

+ (instancetype)shared;

- (BOOL)isShowing;
- (void)toggle;
- (void)present;
- (void)dismiss;

@end
