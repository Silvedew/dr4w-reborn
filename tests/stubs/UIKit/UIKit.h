// Foundation-only UI declarations for testing the production Settings controller.
#import <Foundation/Foundation.h>
#define NSFontAttributeName @"NSFont"
#define NSForegroundColorAttributeName @"NSColor"
#define UIFontTextStyleBody @"body"
#define UIFontTextStyleCaption2 @"caption2"
typedef NS_ENUM(NSInteger, UIImageRenderingMode) { UIImageRenderingModeAlwaysOriginal = 1, UIImageRenderingModeAlwaysTemplate = 2 };

@interface UIImage : NSObject
+ (instancetype)systemImageNamed:(NSString *)name;
- (instancetype)imageWithTintColor:(id)color renderingMode:(UIImageRenderingMode)mode;
- (instancetype)imageWithRenderingMode:(UIImageRenderingMode)mode;
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
+ (instancetype)labelColor;
@end
@interface UILabel : NSObject
@property (nonatomic) NSInteger numberOfLines;
@property (nonatomic, strong) NSAttributedString *attributedText;
@property (nonatomic) BOOL adjustsFontForContentSizeCategory;
@property (nonatomic, copy) NSString *accessibilityLabel;
@end
@interface UITableView : NSObject
@end
@interface UIImageView : NSObject
@property (nonatomic, strong) UIColor *tintColor;
@end
@interface UITableViewCell : NSObject
@property (nonatomic, strong) UILabel *textLabel;
@property (nonatomic, strong) UIImageView *imageView;
@end

@interface UIViewController : NSObject
@property (nonatomic, copy) NSString *title;
- (void)viewDidLoad;
- (void)viewWillAppear:(BOOL)animated;
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion;
@end

@class UISearchController;
@protocol UISearchResultsUpdating <NSObject>
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController;
@end
@interface UISearchBar : NSObject
@property (nonatomic, copy) NSString *text;
@end
@interface UISearchController : UIViewController
- (instancetype)initWithSearchResultsController:(UIViewController *)controller;
@property (nonatomic, weak) id<UISearchResultsUpdating> searchResultsUpdater;
@property (nonatomic) BOOL obscuresBackgroundDuringPresentation;
@property (nonatomic, strong) UISearchBar *searchBar;
@end
@interface UINavigationItem : NSObject
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic) BOOL hidesSearchBarWhenScrolling;
@end
@interface UIViewController (RBNavigationItem)
@property (nonatomic, strong, readonly) UINavigationItem *navigationItem;
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
