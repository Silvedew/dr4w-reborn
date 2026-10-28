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
#define RBSetAppEnabled RBFixtureSetAppEnabled
static void RBFixtureSetAppEnabled(NSString *bundleID, BOOL enabled, void (^completion)(BOOL, NSError *));
#import "../Shared/RBAppCatalog.m"
#import "../Preferences/RBRootListController.m"
#undef NSClassFromString
#undef RBSetAppEnabled
#import "../Shared/RBSettingsStore.m"
#include <assert.h>

static NSMutableDictionary *gIconReads;
@implementation UIImage
+ (instancetype)systemImageNamed:(NSString *)name { return [self new]; }
- (instancetype)imageWithTintColor:(id)color renderingMode:(UIImageRenderingMode)mode { return self; }
- (instancetype)imageWithRenderingMode:(UIImageRenderingMode)mode { return self; }
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
+ (instancetype)preferredFontForTextStyle:(NSString *)style { return [self new]; }
- (CGFloat)lineHeight { return 17; }
@end
@implementation UIColor
+ (instancetype)secondaryLabelColor { return [self new]; }
+ (instancetype)systemBlueColor { return [self new]; }
+ (instancetype)labelColor { return [self new]; }
@end
@implementation UILabel
@end
@implementation UITableView
@end
@implementation UIImageView
@end
@implementation UITableViewCell
- (instancetype)init {
    if ((self = [super init])) {
        self.textLabel = [UILabel new];
        self.imageView = [UIImageView new];
    }
    return self;
}
@end

@implementation UIViewController
- (void)viewDidLoad {}
- (void)viewWillAppear:(BOOL)animated {}
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if (completion) completion();
}
@end
@implementation UISearchBar
@end
@implementation UISearchController
- (instancetype)initWithSearchResultsController:(UIViewController *)controller {
    if ((self = [super init])) self.searchBar = [UISearchBar new];
    return self;
}
@end
@implementation UINavigationItem
@end
@implementation UIViewController (RBNavigationItem)
- (UINavigationItem *)navigationItem {
    static UINavigationItem *item;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ item = [UINavigationItem new]; });
    return item;
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
static NSUInteger gWorkspaceReads;
static BOOL gWorkspaceThrows;
@implementation LSApplicationWorkspace
+ (instancetype)defaultWorkspace { return [self new]; }
- (NSArray *)allInstalledApplications {
    gWorkspaceReads++;
    if (gWorkspaceThrows) @throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];
    return gInstalledApps;
}
@end

static void (^gPendingAppSave)(BOOL, NSError *);
static NSString *gPendingBundle;
static BOOL gPendingEnabled;
static void RBFixtureSetAppEnabled(NSString *bundleID, BOOL enabled, void (^completion)(BOOL, NSError *)) {
    gPendingBundle = [bundleID copy];
    gPendingEnabled = enabled;
    gPendingAppSave = [completion copy];
}

static void CompleteAppSave(BOOL saved) {
    assert(gPendingAppSave != nil);
    if (saved) {
        NSMutableArray *enabledApps = [RBSetting(@"enabledApps", @[]) mutableCopy];
        [enabledApps removeObject:gPendingBundle];
        if (gPendingEnabled) [enabledApps addObject:gPendingBundle];
        assert(RBWriteSetting(@"enabledApps", enabledApps));
    }
    void (^completion)(BOOL, NSError *) = gPendingAppSave;
    gPendingAppSave = nil;
    completion(saved, saved ? nil : [NSError errorWithDomain:@"tests" code:1 userInfo:nil]);
}

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
        assert(rows.count == 7); // Three sections, three switches, installed-app link.
        assert(root.tableSpecifiers.count == rows.count); // Old code leaves this empty.
        assert(root.publishCount == 1);
        assert(root.specifiers == rows);
        assert(root.publishCount == 1); // Repeated access must not rebuild the table.
        assert([[root readPreferenceValue:rows[1]] boolValue]);
        UITableViewCell *pluginCell = [root tableView:nil cellForRowAtIndexPath:[NSIndexPath indexPathWithIndex:1]];
        assert(pluginCell.imageView.tintColor != nil);
        assert([[rows.lastObject propertyForKey:@"label"] isEqualToString:@"App 启用"]);
        for (PSSpecifier *row in rows) assert(![[row propertyForKey:@"key"] isEqualToString:@"showBall"]);
        for (PSSpecifier *row in rows) {
            if ([row propertyForKey:@"key"] || [row propertyForKey:@"detailClass"])
                assert([row propertyForKey:@"iconImage"] != nil);
        }
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
            AppWithInfo(fixtureRoot, @"test.appextension", @{@"NSExtension":@{}}),
            AppWithInfo(fixtureRoot, @"test.malformed-ui-element", @{@"LSUIElement":@[@"bad"]}),
            AppWithInfo(fixtureRoot, @"test.malformed-background", @{@"LSBackgroundOnly":@{@"bad":@YES}})];
        NSArray *installedFixtures = gInstalledApps;
        NSArray *catalog = RBInstalledApplications();
        assert(catalog.count == 4);
        gWorkspaceThrows = YES;
        assert(RBInstalledApplications() == nil);
        gWorkspaceThrows = NO;
        assert(RBFilterApplications(catalog, @"  readER  ").count == 2);
        assert(RBFilterApplications(catalog, @"test.notes").count == 1);
        assert(RBFilterApplications(catalog, @"READER.ALT").count == 1);
        assert(RBFilterApplications(catalog, @" ").count == catalog.count);
        assert(RBFilterApplications(catalog, @"no such app").count == 0);
        assert(RBFilterApplications(catalog, @"").count == catalog.count);
        NSArray *nfc = RBFilterApplications(@[@{@"id":@"test.nfc", @"name":@"Café"}], @"Cafe\u0301");
        assert(nfc.count == 1);
        gInstalledApps = nil;
        assert(RBInstalledApplications() == nil);
        RBAppListController *failedApps = [RBAppListController new];
        assert([[failedApps.specifiers[0] propertyForKey:@"footerText"] containsString:@"无法读取"]);
        gInstalledApps = @[];
        assert(RBInstalledApplications() != nil && RBInstalledApplications().count == 0);
        gInstalledApps = installedFixtures;
        assert(RBWriteSetting(@"enabledApps", @[@"test.hidden"]));
        RBAppListController *apps = [detail new];
        [apps viewDidLoad];
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
        assert(gPendingAppSave != nil && [gPendingBundle isEqualToString:@"test.notes"]);
        assert(![[RowForApp(apps.specifiers, @"test.notes") propertyForKey:@"enabled"] boolValue]);
        [apps setPreferenceValue:@NO specifier:notes]; // Ignore repeated operation while the save is pending.
        assert(gPendingEnabled);
        CompleteAppSave(YES);
        assert([[apps readPreferenceValue:notes] boolValue]);
        assert([[RowForApp(apps.specifiers, @"test.notes") propertyForKey:@"enabled"] boolValue]);
        assert(RBBallForBundle(@"test.notes"));
        assert([RBSetting(@"enabledApps", @[]) containsObject:@"test.hidden"]);
        [apps setPreferenceValue:@NO specifier:notes];
        CompleteAppSave(NO);
        assert([[apps readPreferenceValue:notes] boolValue]);
        assert(RBBallForBundle(@"test.notes"));
        assert([[RowForApp(apps.specifiers, @"test.notes") propertyForKey:@"enabled"] boolValue]);
        NSUInteger readerIndex = [appRows indexOfObject:RowForApp(appRows, @"test.reader")];
        UITableViewCell *cell = [apps tableView:nil cellForRowAtIndexPath:[NSIndexPath indexPathWithIndex:readerIndex]];
        assert([cell.textLabel.attributedText.string isEqualToString:@"Reader\ntest.reader"]);
        assert(cell.textLabel.numberOfLines == 2);
        assert(cell.textLabel.adjustsFontForContentSizeCategory);
        assert([cell.textLabel.accessibilityLabel containsString:@"test.reader"]);
        NSUInteger notesIndex = [appRows indexOfObject:notes];
        cell = [apps tableView:nil cellForRowAtIndexPath:[NSIndexPath indexPathWithIndex:notesIndex]];
        assert(cell.imageView.tintColor == nil); // App icons keep their own colors.
        assert([cell.textLabel.attributedText.string isEqualToString:@"Notes"]);
        assert(cell.textLabel.numberOfLines == 1);
        NSUInteger readsBeforeSearch = gWorkspaceReads;
        apps.rbSearchController.searchBar.text = @"test.reader";
        [apps updateSearchResultsForSearchController:apps.rbSearchController];
        assert(apps.specifiers.count == 3);
        assert(RowForApp(apps.specifiers, @"test.reader") != nil);
        assert(gWorkspaceReads == readsBeforeSearch);
        apps.rbSearchController.searchBar.text = @"missing result";
        [apps updateSearchResultsForSearchController:apps.rbSearchController];
        assert(apps.specifiers.count == 1);
        assert([[apps.specifiers[0] propertyForKey:@"footerText"] containsString:@"没有匹配"]);
        [apps viewWillAppear:YES];
        assert(apps.specifiers.count == 1);
        assert(gWorkspaceReads == readsBeforeSearch);
        apps.rbSearchController.searchBar.text = @"  ";
        [apps updateSearchResultsForSearchController:apps.rbSearchController];
        assert(apps.specifiers.count == appRows.count);
        assert(gWorkspaceReads == readsBeforeSearch);
        assert([gIconReads[@"test.reader"] integerValue] == 1);
        id firstIcon = [notes propertyForKey:@"iconImage"];
        [apps reloadSpecifiers];
        assert([RowForApp(apps.specifiers, @"test.notes") propertyForKey:@"iconImage"] == firstIcon);
        assert([gIconReads[@"test.notes"] integerValue] == 1);
        assert([gIconReads[@"test.noicon"] integerValue] == 1);

        [root reloadSpecifiers];
        assert(root.specifiers.count == 7);
        assert(root.publishCount == 2);
        assert(root.tableSpecifiers.count == 7);
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
