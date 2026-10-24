#import <UIKit/UIKit.h>
@class PSSpecifier;

// Minimal declarations from theos/headers Preferences and MobileCoreServices.
@interface PSViewController : UIViewController
@end
@interface PSListController : PSViewController
@property (nonatomic, strong) NSMutableArray *specifiers;
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)reloadSpecifiers;
@end
@interface PSSpecifier : NSObject
+ (instancetype)groupSpecifierWithName:(NSString *)name;
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set
    get:(SEL)get detail:(Class)detail cell:(NSInteger)cell edit:(Class)edit;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly, getter=isInstalled) BOOL installed;
@property (nonatomic, readonly, getter=isPlaceholder) BOOL placeholder;
@property (nonatomic, readonly, getter=isLaunchProhibited) BOOL launchProhibited;
@property (nonatomic, readonly) NSURL *bundleURL;
@end

@interface UIImage (RBApplicationIcon)
+ (instancetype)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(NSInteger)format scale:(CGFloat)scale;
@end
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
@end
