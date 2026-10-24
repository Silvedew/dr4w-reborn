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
#import "../Shared/RBSettingsStore.m"
#include <assert.h>

static NSMutableDictionary *gIconReads;
@implementation UIImage
+ (instancetype)systemImageNamed:(NSString *)name { return [self new]; }
+ (instancetype)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(NSInteger)format scale:(CGFloat)scale {
    if (!gIconReads) gIconReads = [NSMutableDictionary dictionary];
    gIconReads[bundleID] = @([gIconReads[bundleID] integerValue] + 1);
    return [bundleID isEqualToString:@"test.noicon"] ? nil : [self new];
}
@end
@implementation UIScreen
+ (instancetype)mainScreen { return [self new]; }
- (CGFloat)scale { return 2; }
@end
@implementation UIFont
+ (instancetype)systemFontOfSize:(CGFloat)size { return [self new]; }
@end
@implementation UIColor
+ (instancetype)secondaryLabelColor { return [self new]; }
@end
@implementation UILabel
@end
@implementation UITableView
@end
@implementation UITableViewCell
- (instancetype)init {
    if ((self = [super init])) self.textLabel = [UILabel new];
    return self;
}
@end

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
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath {
    return self.specifiers[[indexPath indexAtPosition:0]];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [UITableViewCell new];
}
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
@property (nonatomic, readwrite, getter=isInstalled) BOOL installed;
@property (nonatomic, readwrite, getter=isPlaceholder) BOOL placeholder;
@property (nonatomic, readwrite, getter=isLaunchProhibited) BOOL launchProhibited;
@property (nonatomic, strong, readwrite) NSURL *bundleURL;
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
    app.installed = YES;
    return app;
}

static LSApplicationProxy *AppWithInfo(NSURL *root, NSString *identifier, NSDictionary *info) {
    LSApplicationProxy *app = App(identifier, @"Reader");
    app.bundleURL = [root URLByAppendingPathComponent:[identifier stringByAppendingString:@".app"]];
    assert([[NSFileManager defaultManager] createDirectoryAtURL:app.bundleURL
        withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([info writeToURL:[app.bundleURL URLByAppendingPathComponent:@"Info.plist"] atomically:YES]);
    return app;
}

static PSSpecifier *RowForApp(NSArray *rows, NSString *bundleID) {
    for (PSSpecifier *row in rows)
        if ([[row propertyForKey:@"appID"] isEqualToString:bundleID]) return row;
    return nil;
}

int main(void) {
    @autoreleasepool {
        for (NSString *key in @[@"enabledApps", @"showBall"]) assert(RBWriteSetting(key, nil));
        RBRootListController *root = [RBRootListController new];
        NSArray *rows = root.specifiers;
        assert(rows.count == 5); // Group, three switches, installed-app link.
        assert(root.tableSpecifiers.count == rows.count); // Old code leaves this empty.
        assert(root.publishCount == 1);
        assert(root.specifiers == rows);
        assert(root.publishCount == 1); // Repeated access must not rebuild the table.
        assert([[root readPreferenceValue:rows[1]] boolValue]);
        assert([[rows.lastObject propertyForKey:@"label"] isEqualToString:@"App 启用"]);
        for (PSSpecifier *row in rows) assert(![[row propertyForKey:@"key"] isEqualToString:@"showBall"]);
        Class detail = [rows.lastObject propertyForKey:@"detailClass"];
        assert(detail == [RBAppListController class]);

        NSURL *fixtureRoot = [NSURL fileURLWithPath:[NSTemporaryDirectory()
            stringByAppendingPathComponent:[@"rb-app-fixtures-" stringByAppendingString:NSUUID.UUID.UUIDString]]];
        LSApplicationProxy *placeholder = App(@"test.placeholder", @"Reader");
        placeholder.placeholder = YES;
        LSApplicationProxy *removed = App(@"test.removed", @"Reader");
        removed.installed = NO;
        LSApplicationProxy *prohibited = App(@"test.prohibited", @"Reader");
        prohibited.launchProhibited = YES;
        LSApplicationProxy *extension = App(@"test.extension", @"Reader");
        extension.bundleURL = [fixtureRoot URLByAppendingPathComponent:@"Helper.appex"];
        gInstalledApps = @[App(@"test.reader", @"Reader"), App(@"test.notes", @"Notes"),
            App(@"test.reader", @"Duplicate"), App(@"com.apple.springboard", @"Home"),
            App(@"test.reader.alt", @"Reader"), App(@"test.noicon", @"Missing Icon"),
            placeholder, removed, prohibited, extension,
            AppWithInfo(fixtureRoot, @"test.hidden", @{@"SBAppTags":@[@"hidden"]}),
            AppWithInfo(fixtureRoot, @"test.background", @{@"LSBackgroundOnly":@YES}),
            AppWithInfo(fixtureRoot, @"test.helper", @{@"LSUIElement":@YES}),
            AppWithInfo(fixtureRoot, @"test.bundle", @{@"CFBundlePackageType":@"BNDL"}),
            AppWithInfo(fixtureRoot, @"test.appextension", @{@"NSExtension":@{}})];
        assert(RBWriteSetting(@"enabledApps", @[@"test.hidden"]));
        RBAppListController *apps = [detail new];
        NSArray *appRows = apps.specifiers;
        assert([apps.title isEqualToString:@"App 启用"]);
        assert(appRows.count == 5); // Group plus four real apps.
        assert(apps.tableSpecifiers.count == appRows.count);
        assert([[RBSetting(@"enabledApps", @[]) firstObject] isEqualToString:@"test.hidden"]);
        PSSpecifier *notes = RowForApp(appRows, @"test.notes");
        assert(notes != nil && [notes propertyForKey:@"iconImage"] != nil);
        assert([RowForApp(appRows, @"test.noicon") propertyForKey:@"iconImage"] != nil);
        assert([RowForApp(appRows, @"test.reader") propertyForKey:@"appSubtitle"] != nil);
        assert([RowForApp(appRows, @"test.reader.alt") propertyForKey:@"appSubtitle"] != nil);
        assert([notes propertyForKey:@"appSubtitle"] == nil);
        for (NSString *bundleID in @[@"test.hidden", @"test.removed", @"test.placeholder", @"test.extension",
            @"test.prohibited", @"test.background", @"test.helper", @"test.bundle", @"test.appextension"])
            assert(RowForApp(appRows, bundleID) == nil);
        assert(![[apps readPreferenceValue:notes] boolValue]);
        [apps setPreferenceValue:@YES specifier:notes];
        assert([[apps readPreferenceValue:notes] boolValue]);
        assert(RBBallForBundle(@"test.notes"));
        assert([RBSetting(@"enabledApps", @[]) containsObject:@"test.hidden"]);
        [apps setPreferenceValue:@NO specifier:notes];
        assert(![[apps readPreferenceValue:notes] boolValue]);
        assert(!RBBallForBundle(@"test.notes"));
        NSUInteger readerIndex = [appRows indexOfObject:RowForApp(appRows, @"test.reader")];
        UITableViewCell *cell = [apps tableView:nil cellForRowAtIndexPath:[NSIndexPath indexPathWithIndex:readerIndex]];
        assert([cell.textLabel.attributedText.string isEqualToString:@"Reader\ntest.reader"]);
        assert(cell.textLabel.numberOfLines == 2);
        NSUInteger notesIndex = [appRows indexOfObject:notes];
        cell = [apps tableView:nil cellForRowAtIndexPath:[NSIndexPath indexPathWithIndex:notesIndex]];
        assert([cell.textLabel.attributedText.string isEqualToString:@"Notes"]);
        assert(cell.textLabel.numberOfLines == 1);
        id firstIcon = [notes propertyForKey:@"iconImage"];
        [apps reloadSpecifiers];
        assert([RowForApp(apps.specifiers, @"test.notes") propertyForKey:@"iconImage"] == firstIcon);
        assert([gIconReads[@"test.notes"] integerValue] == 1);
        assert([gIconReads[@"test.noicon"] integerValue] == 1);

        [root reloadSpecifiers];
        assert(root.specifiers.count == 5);
        assert(root.publishCount == 2);
        assert(root.tableSpecifiers.count == 5);
        gInstalledApps = @[];
        [apps reloadSpecifiers];
        assert(apps.specifiers.count == 1); // A visible explanation, not a blank page.
        assert(apps.tableSpecifiers.count == 1);
        assert([[apps.specifiers[0] propertyForKey:@"footerText"] length] > 0);
        for (NSString *key in @[@"enabledApps", @"showBall"]) assert(RBWriteSetting(key, nil));
        assert([[NSFileManager defaultManager] removeItemAtURL:fixtureRoot error:NULL]);
        NSLog(@"Root/app Settings table storage, reload, and switch tests passed.");
    }
    return 0;
}
