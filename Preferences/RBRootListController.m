#import "RBPreferencesPrivate.h"
#import "RBSettings.h"

@interface RBSettingsListController : PSListController
@property (nonatomic, strong) NSArray *rbSpecifiers;
- (PSSpecifier *)switchNamed:(NSString *)name key:(NSString *)key defaultValue:(BOOL)value;
@end

@interface RBAppListController : RBSettingsListController
@end
@interface RBRootListController : RBSettingsListController
@end

@implementation RBSettingsListController
- (PSSpecifier *)switchNamed:(NSString *)name key:(NSString *)key defaultValue:(BOOL)value {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:)
        detail:Nil cell:6 edit:Nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(value) forKey:@"default"];
    return specifier;
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
        key = @"enabledApps";
        id current = RBSetting(key, @[]);
        NSMutableArray *apps = [current isKindOfClass:[NSArray class]]
            ? [current mutableCopy] : [NSMutableArray array];
        [apps removeObject:appID];
        if ([value boolValue]) [apps addObject:appID];
        stored = apps;
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
- (NSArray *)specifiers {
    if (self.rbSpecifiers) return self.rbSpecifiers;
    self.title = @"全局画板";
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Dr4w Reborn"];
    [group setProperty:@"App 默认不启用，圆球默认隐藏。启用某个 App 后，音量加→音量减可打开画板，不需要显示圆球。修改立即生效。"
        forKey:@"footerText"];
    PSSpecifier *apps = [PSSpecifier preferenceSpecifierNamed:@"在哪些 App 启用" target:self
        set:NULL get:NULL detail:[RBAppListController class] cell:1 edit:Nil];
    self.rbSpecifiers = @[group,
        [self switchNamed:@"启用插件" key:@"enabled" defaultValue:YES],
        [self switchNamed:@"在主屏幕启用" key:@"homeEnabled" defaultValue:YES],
        [self switchNamed:@"音量加→音量减快捷键" key:@"volumeShortcutEnabled" defaultValue:YES],
        [self switchNamed:@"在已启用的 App 显示圆球" key:@"showBall" defaultValue:NO], apps];
    return self.rbSpecifiers;
}
@end

@implementation RBAppListController
- (NSArray *)specifiers {
    if (self.rbSpecifiers) return self.rbSpecifiers;
    self.title = @"在哪些 App 启用";
    NSMutableArray *specifiers = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"按 App 开启"];
    [group setProperty:@"关闭的 App 不响应画板快捷键，也不显示圆球。分屏时各 App 按自己的开关生效。"
        forKey:@"footerText"];
    [specifiers addObject:group];
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    LSApplicationWorkspace *workspace = [cls respondsToSelector:@selector(defaultWorkspace)]
        ? [cls defaultWorkspace] : nil;
    NSArray *installed = [workspace respondsToSelector:@selector(allInstalledApplications)]
        ? [workspace allInstalledApplications] : @[];
    NSMutableArray<NSDictionary *> *apps = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (LSApplicationProxy *app in installed) {
        if (![app respondsToSelector:@selector(applicationIdentifier)]) continue;
        NSString *appID = app.applicationIdentifier;
        if (![appID isKindOfClass:[NSString class]] || !appID.length || [seen containsObject:appID] ||
            [appID isEqualToString:@"com.apple.springboard"]) continue;
        NSString *name = [app respondsToSelector:@selector(localizedName)] ? app.localizedName : nil;
        [apps addObject:@{@"id":appID, @"name":name ?: appID}];
        [seen addObject:appID];
    }
    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedStandardCompare:b[@"name"]];
    }];
    for (NSDictionary *app in apps) {
        PSSpecifier *specifier = [self switchNamed:app[@"name"] key:@"enabledApps" defaultValue:NO];
        [specifier setProperty:app[@"id"] forKey:@"appID"];
        [specifiers addObject:specifier];
    }
    if (!apps.count) [group setProperty:@"无法读取已安装 App 列表，请重新打开设置后重试。" forKey:@"footerText"];
    self.rbSpecifiers = specifiers;
    return self.rbSpecifiers;
}
@end
