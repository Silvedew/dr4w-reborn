// Compile the actual controller against a small Preferences/UIKit host.
// This tests controller-to-table storage, not iPad rendering or PreferenceLoader.
#define RB_SETTINGS_DOMAIN @"com.dsh.dr4wreborn.controller-tests"
#import <Foundation/Foundation.h>

// macOS already loads LaunchServices; keep fixtures out of its class namespace.
static Class RBTestLookupClass(NSString *name) {
    return NSClassFromString([name isEqualToString:@"LSApplicationWorkspace"]
        ? @"RBFixtureApplicationWorkspace" : name);
}
#define LSApplicationProxy RBFixtureApplicationProxy
#define LSApplicationWorkspace RBFixtureApplicationWorkspace
#define NSClassFromString RBTestLookupClass
#import "../Preferences/RBRootListController.m"
#undef NSClassFromString
#include <assert.h>

@implementation UIViewController
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if (completion) completion();
}
@end
@implementation UIAlertAction
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler {
    return [self new];
}
@end
@implementation UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style {
    return [self new];
}
- (void)addAction:(UIAlertAction *)action {}
@end

@implementation PSViewController
@end
@interface PSListController ()
@property (nonatomic, strong) NSMutableArray *tableSpecifiers;
@property (nonatomic) NSUInteger publishCount;
@end
@implementation PSListController
- (NSMutableArray *)specifiers { return self.tableSpecifiers; }
- (void)setSpecifiers:(NSMutableArray *)specifiers {
    self.tableSpecifiers = specifiers;
    self.publishCount++;
    // A host may consult the getter while installing the table model.
    if (specifiers) assert([self specifiers] != nil);
}
- (void)reloadSpecifiers { self.tableSpecifiers = nil; }
@end

@interface PSSpecifier ()
@property (nonatomic, strong) NSMutableDictionary *values;
@end
@implementation PSSpecifier
+ (instancetype)groupSpecifierWithName:(NSString *)name {
    PSSpecifier *specifier = [self new];
    specifier.values = [@{@"label":name} mutableCopy];
    return specifier;
}
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set
    get:(SEL)get detail:(Class)detail cell:(NSInteger)cell edit:(Class)edit {
    PSSpecifier *specifier = [self groupSpecifierWithName:name];
    [specifier setProperty:@(cell) forKey:@"cell"];
    if (detail) [specifier setProperty:detail forKey:@"detailClass"];
    return specifier;
}
- (void)setProperty:(id)value forKey:(NSString *)key { self.values[key] = value; }
- (id)propertyForKey:(NSString *)key { return self.values[key]; }
@end

@interface LSApplicationProxy ()
@property (nonatomic, copy, readwrite) NSString *applicationIdentifier;
@property (nonatomic, copy, readwrite) NSString *localizedName;
@end
@implementation LSApplicationProxy
@end
static NSArray *gInstalledApps;
@implementation LSApplicationWorkspace
+ (instancetype)defaultWorkspace { return [self new]; }
- (NSArray *)allInstalledApplications { return gInstalledApps; }
@end

static LSApplicationProxy *App(NSString *identifier, NSString *name) {
    LSApplicationProxy *app = [LSApplicationProxy new];
    app.applicationIdentifier = identifier;
    app.localizedName = name;
    return app;
}

int main(void) {
    @autoreleasepool {
        for (NSString *key in @[@"enabledApps", @"showBall"]) assert(RBWriteSetting(key, nil));
        RBRootListController *root = [RBRootListController new];
        NSArray *rows = root.specifiers;
        assert(rows.count == 6); // Group, four switches, installed-app link.
        assert(root.tableSpecifiers.count == rows.count); // Old code leaves this empty.
        assert(root.publishCount == 1);
        assert(root.specifiers == rows);
        assert(root.publishCount == 1); // Repeated access must not rebuild the table.
        assert([[root readPreferenceValue:rows[1]] boolValue]);
        assert(![[root readPreferenceValue:rows[4]] boolValue]);
        Class detail = [rows.lastObject propertyForKey:@"detailClass"];
        assert(detail == [RBAppListController class]);

        gInstalledApps = @[App(@"test.reader", @"Reader"), App(@"test.notes", @"Notes"),
            App(@"test.reader", @"Duplicate"), App(@"com.apple.springboard", @"Home")];
        RBAppListController *apps = [detail new];
        NSArray *appRows = apps.specifiers;
        assert(appRows.count == 3); // Group plus two unique apps, no SpringBoard.
        assert(apps.tableSpecifiers.count == appRows.count);
        assert([[[appRows[1] propertyForKey:@"label"] description] isEqualToString:@"Notes"]);
        assert(![[apps readPreferenceValue:appRows[1]] boolValue]);
        [apps setPreferenceValue:@YES specifier:appRows[1]];
        assert([[apps readPreferenceValue:appRows[1]] boolValue]);
        assert(![[root readPreferenceValue:rows[4]] boolValue]); // App on, ball still off.
        [apps setPreferenceValue:@NO specifier:appRows[1]];
        assert(![[apps readPreferenceValue:appRows[1]] boolValue]);

        [root reloadSpecifiers];
        assert(root.specifiers.count == 6);
        assert(root.publishCount == 2);
        assert(root.tableSpecifiers.count == 6);
        gInstalledApps = @[];
        [apps reloadSpecifiers];
        assert(apps.specifiers.count == 1); // A visible explanation, not a blank page.
        assert(apps.tableSpecifiers.count == 1);
        assert([[apps.specifiers[0] propertyForKey:@"footerText"] length] > 0);
        for (NSString *key in @[@"enabledApps", @"showBall"]) assert(RBWriteSetting(key, nil));
        NSLog(@"Root/app Settings table storage, reload, and switch tests passed.");
    }
    return 0;
}
