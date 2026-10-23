#import <UIKit/UIKit.h>

void RBWriteLog(NSString *text);

@interface RBManager : NSObject

+ (instancetype)shared;

- (BOOL)isShowing;
- (void)toggle;
- (void)present;
- (void)dismiss;

@end
