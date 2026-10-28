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
