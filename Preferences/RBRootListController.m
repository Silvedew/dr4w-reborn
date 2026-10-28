#import "RBPreferencesPrivate.h"
#import "RBSettings.h"
#import "RBIconStyle.h"
#import "../Shared/RBAppCatalog.h"
#import "../Shared/RBApplicationIcon.h"
#include <math.h>

static UIImage *RBSettingsIcon(NSString *symbol) {
    return [[UIImage systemImageNamed:symbol] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@interface RBSettingsListController : PSListController
@property (nonatomic, strong) NSMutableArray *rbSpecifiers;
@property (nonatomic, strong) NSMutableSet<NSString *> *rbPendingApps;
- (PSSpecifier *)switchNamed:(NSString *)name key:(NSString *)key defaultValue:(BOOL)value;
- (void)publishSpecifiers:(NSArray *)specifiers;
@end

@interface RBAppListController : RBSettingsListController <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<NSDictionary *> *rbApplications;
@property (nonatomic) BOOL rbLoadedApplications;
@property (nonatomic, strong) UISearchController *rbSearchController;
- (void)showApplicationsMatching:(NSString *)query;
- (void)refreshVisibleSpecifiers;
- (NSString *)currentSearchQuery;
@end
@interface RBRootListController : RBSettingsListController
@end

@implementation RBSettingsListController
- (void)publishSpecifiers:(NSArray *)specifiers {
    // PSListController builds its table from its own specifier storage.
    self.rbSpecifiers = [specifiers mutableCopy];
    [super setSpecifiers:self.rbSpecifiers];
}

- (void)reloadSpecifiers {
    self.rbSpecifiers = nil;
    [super reloadSpecifiers];
}

- (PSSpecifier *)switchNamed:(NSString *)name key:(NSString *)key defaultValue:(BOOL)value {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:)
        detail:Nil cell:6 edit:Nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(value) forKey:@"default"];
    NSString *symbol = @{@"enabled": @RB_PENCIL_SYMBOL, @"homeEnabled": @"house",
        @"volumeShortcutEnabled": @"speaker.wave.2"}[key];
    if (symbol) {
        [specifier setProperty:RBSettingsIcon(symbol) forKey:@"iconImage"];
        [specifier setProperty:@YES forKey:@"rbMonochromeIcon"];
    }
    return specifier;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if ([[[self specifierAtIndexPath:indexPath] propertyForKey:@"rbMonochromeIcon"] boolValue])
        cell.imageView.tintColor = UIColor.labelColor;
    return cell;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    RBReloadSettings();
    NSString *appID = [specifier propertyForKey:@"appID"];
    if (appID) {
        id apps = RBSetting(@"enabledApps", @[]);
        return @([apps isKindOfClass:[NSArray class]] && [apps containsObject:appID]);
    }
    return @(RBSettingBool([specifier propertyForKey:@"key"],
        [[specifier propertyForKey:@"default"] boolValue]));
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    RBReloadSettings();
    NSString *appID = [specifier propertyForKey:@"appID"];
    NSString *key = [specifier propertyForKey:@"key"];
    id stored = @([value boolValue]);
    if (appID) {
        if (!self.rbPendingApps) self.rbPendingApps = [NSMutableSet set];
        if ([self.rbPendingApps containsObject:appID]) return;
        [self.rbPendingApps addObject:appID];
        [(RBAppListController *)self refreshVisibleSpecifiers];
        RBSetAppEnabled(appID, [value boolValue], ^(BOOL saved, NSError *error) {
            [self.rbPendingApps removeObject:appID];
            [(RBAppListController *)self refreshVisibleSpecifiers];
            if (saved) return;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
                message:error.localizedDescription ?: @"请检查偏好设置文件的写入权限后重试。"
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
        return;
    }
    if (!RBWriteSetting(key, stored)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:@"请检查偏好设置文件的写入权限后重试。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
    }
}
@end

@implementation RBRootListController
- (NSMutableArray *)specifiers {
    if (self.rbSpecifiers) return self.rbSpecifiers;
    self.title = @"全局画板";
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"全局画板"];
    [group setProperty:@"关闭后，所有 App 中的画板与快捷键均停用。"
        forKey:@"footerText"];
    PSSpecifier *launch = [PSSpecifier groupSpecifierWithName:@"唤醒方式"];
    [launch setProperty:@"依次按音量加、音量减，可打开或关闭画板。" forKey:@"footerText"];
    PSSpecifier *appGroup = [PSSpecifier groupSpecifierWithName:@"应用"];
    [appGroup setProperty:@"启用 App 后显示圆球，轻点打开画板。长按临时隐藏，再次进入 App 恢复。"
        forKey:@"footerText"];
    PSSpecifier *apps = [PSSpecifier preferenceSpecifierNamed:@"App 启用" target:self
        set:NULL get:NULL detail:[RBAppListController class] cell:1 edit:Nil];
    [apps setProperty:RBSettingsIcon(@"app.badge") forKey:@"iconImage"];
    [apps setProperty:@YES forKey:@"rbMonochromeIcon"];
    [self publishSpecifiers:@[group,
        [self switchNamed:@"启用画板" key:@"enabled" defaultValue:YES], launch,
        [self switchNamed:@"在主屏幕启用" key:@"homeEnabled" defaultValue:YES],
        [self switchNamed:@"音量快捷键" key:@"volumeShortcutEnabled" defaultValue:YES], appGroup, apps]];
    return self.rbSpecifiers;
}
@end

@implementation RBAppListController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.rbSearchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.rbSearchController.searchResultsUpdater = self;
    self.rbSearchController.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = self.rbSearchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    __weak typeof(self) weakSelf = self;
    RBObserveSettings(^{
        [weakSelf refreshVisibleSpecifiers];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    RBReloadSettings();
    [self refreshVisibleSpecifiers];
}

- (NSString *)currentSearchQuery {
    return self.rbSearchController.searchBar.text ?: @"";
}

- (void)refreshVisibleSpecifiers {
    if (!self.rbSpecifiers) return;
    self.rbSpecifiers = nil;
    [self showApplicationsMatching:[self currentSearchQuery]];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self showApplicationsMatching:searchController.searchBar.text ?: @""];
}

- (void)showApplicationsMatching:(NSString *)query {
    if (!self.rbLoadedApplications) {
        self.rbApplications = RBInstalledApplications();
        self.rbLoadedApplications = YES;
    }
    BOOL failed = self.rbApplications == nil;
    NSArray *matches = failed ? @[] : RBFilterApplications(self.rbApplications, query);
    NSMutableArray *specifiers = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"按 App 开启"];
    [group setProperty:@"关闭的 App 不响应画板快捷键，也不显示圆球。分屏时各 App 按自己的开关生效。"
        forKey:@"footerText"];
    [specifiers addObject:group];
    for (NSDictionary *app in matches) {
        PSSpecifier *specifier = [self switchNamed:app[@"name"] key:@"enabledApps" defaultValue:NO];
        [specifier setProperty:app[@"id"] forKey:@"appID"];
        [specifier setProperty:app[@"name"] forKey:@"appName"];
        UIImage *icon = RBApplicationIcon(app[@"id"]);
        if (icon) [specifier setProperty:icon forKey:@"iconImage"];
        NSString *subtitle = app[@"subtitle"];
        if (subtitle) {
            [specifier setProperty:subtitle forKey:@"appSubtitle"];
            CGFloat height = MAX(54, ceil([UIFont preferredFontForTextStyle:UIFontTextStyleBody].lineHeight +
                [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2].lineHeight + 18));
            [specifier setProperty:@(height) forKey:@"height"];
        }
        [specifier setProperty:@(![self.rbPendingApps containsObject:app[@"id"]]) forKey:@"enabled"];
        [specifiers addObject:specifier];
    }
    if (failed) [group setProperty:@"无法读取已安装 App 列表，请重新打开设置后重试。" forKey:@"footerText"];
    else if (!self.rbApplications.count) [group setProperty:@"没有已安装的可用 App。" forKey:@"footerText"];
    else if (!matches.count) [group setProperty:@"没有匹配的 App。清除搜索内容可恢复完整列表。" forKey:@"footerText"];
    [self publishSpecifiers:specifiers];
}

- (NSMutableArray *)specifiers {
    if (self.rbSpecifiers) return self.rbSpecifiers;
    self.title = @"App 启用";
    [self showApplicationsMatching:[self currentSearchQuery]];
    return self.rbSpecifiers;
}

- (void)reloadSpecifiers {
    self.rbSpecifiers = nil;
    self.rbLoadedApplications = NO;
    [self showApplicationsMatching:[self currentSearchQuery]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *name = [specifier propertyForKey:@"appName"] ?: @"";
    NSString *subtitle = [specifier propertyForKey:@"appSubtitle"];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc]
        initWithString:subtitle ? [NSString stringWithFormat:@"%@\n%@", name, subtitle] : name];
    if (subtitle) [text addAttributes:@{NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleCaption2],
        NSForegroundColorAttributeName:[UIColor secondaryLabelColor]}
        range:NSMakeRange(name.length + 1, subtitle.length)];
    cell.textLabel.numberOfLines = subtitle ? 2 : 1;
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.accessibilityLabel = subtitle ? [NSString stringWithFormat:@"%@，%@", name, subtitle] : name;
    cell.textLabel.attributedText = text;
    return cell;
}
@end
