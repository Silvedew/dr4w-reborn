#import <UIKit/UIKit.h>

// Minimal declarations from theos/headers Preferences and MobileCoreServices.
@interface PSViewController : UIViewController
@end
@interface PSListController : PSViewController
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
@end
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
@end
