#import "RBPreferencesPrivate.h"
#import "RBSettings.h"

static BOOL RBNormalApplication(LSApplicationProxy *app) {
    if ([app respondsToSelector:@selector(isInstalled)] && !app.isInstalled) return NO;
    if ([app respondsToSelector:@selector(isPlaceholder)] && app.isPlaceholder) return NO;
    if ([app respondsToSelector:@selector(isLaunchProhibited)] && app.isLaunchProhibited) return NO;
    NSURL *url = [app respondsToSelector:@selector(bundleURL)] ? app.bundleURL : nil;
    if (url) {
        if (![url.pathExtension.lowercaseString isEqualToString:@"app"]) return NO;
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:[url URLByAppendingPathComponent:@"Info.plist"]];
        if (info[@"NSExtension"] || [info[@"LSUIElement"] boolValue] || [info[@"LSBackgroundOnly"] boolValue]) return NO;
        NSString *type = info[@"CFBundlePackageType"];
        if (type && ![type isEqualToString:@"APPL"]) return NO;
        id tags = info[@"SBAppTags"];
        if ([tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"]) return NO;
    }
    return YES;
}

static UIImage *RBApplicationIcon(NSString *bundleID) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 256; });
    UIImage *icon = [cache objectForKey:bundleID];
    if (icon) return icon;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:[UIScreen mainScreen].scale];
    if (!icon) icon = [UIImage systemImageNamed:@"app"];
    if (icon) [cache setObject:icon forKey:bundleID];
    return icon;
}

@interface RBSettingsListController : PSListController
@property (nonatomic, strong) NSMutableArray *rbSpecifiers;
- (PSSpecifier *)switchNamed:(NSString *)name key:(NSString *)key defaultValue:(BOOL)value;
- (void)publishSpecifiers:(NSArray *)specifiers;
@end

@interface RBAppListController : RBSettingsListController
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
- (NSMutableArray *)specifiers {
    if (self.rbSpecifiers) return self.rbSpecifiers;
    self.title = @"全局画板";
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Dr4w Reborn"];
    [group setProperty:@"App 默认不启用。在「App 启用」中开启后，进入该 App 即显示圆球，点击即可打开画板。长按只在本次使用中隐藏圆球。修改立即生效。"
        forKey:@"footerText"];
    PSSpecifier *apps = [PSSpecifier preferenceSpecifierNamed:@"App 启用" target:self
        set:NULL get:NULL detail:[RBAppListController class] cell:1 edit:Nil];
    [self publishSpecifiers:@[group,
        [self switchNamed:@"启用插件" key:@"enabled" defaultValue:YES],
        [self switchNamed:@"在主屏幕启用" key:@"homeEnabled" defaultValue:YES],
        [self switchNamed:@"音量加→音量减快捷键" key:@"volumeShortcutEnabled" defaultValue:YES], apps]];
    return self.rbSpecifiers;
}
@end

@implementation RBAppListController
- (NSMutableArray *)specifiers {
    if (self.rbSpecifiers) return self.rbSpecifiers;
    self.title = @"App 启用";
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
    NSMutableDictionary<NSString *, NSNumber *> *nameCounts = [NSMutableDictionary dictionary];
    for (LSApplicationProxy *app in installed) {
        if (![app respondsToSelector:@selector(applicationIdentifier)]) continue;
        NSString *appID = app.applicationIdentifier;
        if (![appID isKindOfClass:[NSString class]] || !appID.length || [seen containsObject:appID] ||
            [appID isEqualToString:@"com.apple.springboard"]) continue;
        if (!RBNormalApplication(app)) continue;
        NSString *name = [app respondsToSelector:@selector(localizedName)] ? app.localizedName : nil;
        if (![name isKindOfClass:[NSString class]] || !name.length) name = appID;
        name = [name precomposedStringWithCanonicalMapping];
        [apps addObject:@{@"id":appID, @"name":name}];
        nameCounts[name] = @([nameCounts[name] unsignedIntegerValue] + 1);
        [seen addObject:appID];
    }
    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult result = [a[@"name"] localizedStandardCompare:b[@"name"]];
        return result == NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : result;
    }];
    for (NSDictionary *app in apps) {
        PSSpecifier *specifier = [self switchNamed:app[@"name"] key:@"enabledApps" defaultValue:NO];
        [specifier setProperty:app[@"id"] forKey:@"appID"];
        [specifier setProperty:app[@"name"] forKey:@"appName"];
        UIImage *icon = RBApplicationIcon(app[@"id"]);
        if (icon) [specifier setProperty:icon forKey:@"iconImage"];
        if ([nameCounts[app[@"name"]] unsignedIntegerValue] > 1) {
            [specifier setProperty:app[@"id"] forKey:@"appSubtitle"];
            [specifier setProperty:@54 forKey:@"height"];
        }
        [specifiers addObject:specifier];
    }
    if (!apps.count) [group setProperty:@"无法读取已安装 App 列表，请重新打开设置后重试。" forKey:@"footerText"];
    [self publishSpecifiers:specifiers];
    return self.rbSpecifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *name = [specifier propertyForKey:@"appName"] ?: @"";
    NSString *subtitle = [specifier propertyForKey:@"appSubtitle"];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc]
        initWithString:subtitle ? [NSString stringWithFormat:@"%@\n%@", name, subtitle] : name];
    if (subtitle) [text addAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:11],
        NSForegroundColorAttributeName:[UIColor secondaryLabelColor]}
        range:NSMakeRange(name.length + 1, subtitle.length)];
    cell.textLabel.numberOfLines = subtitle ? 2 : 1;
    cell.textLabel.attributedText = text;
    return cell;
}
@end
