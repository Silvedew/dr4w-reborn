// Foundation-only UI declarations for testing the production Settings controller.
#import <Foundation/Foundation.h>
#define NSFontAttributeName @"NSFont"
#define NSForegroundColorAttributeName @"NSColor"
#define UIFontTextStyleBody @"body"
#define UIFontTextStyleCaption2 @"caption2"
typedef NS_ENUM(NSInteger, UIImageRenderingMode) { UIImageRenderingModeAlwaysOriginal = 1 };

@interface UIImage : NSObject
+ (instancetype)systemImageNamed:(NSString *)name;
- (instancetype)imageWithTintColor:(id)color renderingMode:(UIImageRenderingMode)mode;
@end
@interface UIScreen : NSObject
+ (instancetype)mainScreen;
@property (nonatomic, readonly) CGFloat scale;
@end
@interface UIFont : NSObject
+ (instancetype)systemFontOfSize:(CGFloat)size;
+ (instancetype)preferredFontForTextStyle:(NSString *)style;
@property (nonatomic, readonly) CGFloat lineHeight;
@end
@interface UIColor : NSObject
+ (instancetype)secondaryLabelColor;
+ (instancetype)systemBlueColor;
@end
@interface UILabel : NSObject
@property (nonatomic) NSInteger numberOfLines;
@property (nonatomic, strong) NSAttributedString *attributedText;
@property (nonatomic) BOOL adjustsFontForContentSizeCategory;
@property (nonatomic, copy) NSString *accessibilityLabel;
@end
@interface UITableView : NSObject
@end
@interface UITableViewCell : NSObject
@property (nonatomic, strong) UILabel *textLabel;
@end

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
