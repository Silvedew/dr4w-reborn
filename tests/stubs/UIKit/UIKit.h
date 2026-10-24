// Foundation-only UI declarations for testing the production Settings controller.
#import <Foundation/Foundation.h>

@interface UIViewController : NSObject
@property (nonatomic, copy) NSString *title;
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion;
@end

typedef NS_ENUM(NSInteger, UIAlertControllerStyle) { UIAlertControllerStyleAlert = 1 };
typedef NS_ENUM(NSInteger, UIAlertActionStyle) { UIAlertActionStyleDefault = 0 };
@interface UIAlertAction : NSObject
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler;
@end
@interface UIAlertController : UIViewController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style;
- (void)addAction:(UIAlertAction *)action;
@end
