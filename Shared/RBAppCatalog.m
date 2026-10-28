#import "RBAppCatalog.h"

// LaunchServices interfaces used by both the Settings bundle and privileged bridge.
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly, getter=isInstalled) BOOL installed;
@property (nonatomic, readonly, getter=isPlaceholder) BOOL placeholder;
@property (nonatomic, readonly, getter=isLaunchProhibited) BOOL launchProhibited;
@property (nonatomic, readonly) NSURL *bundleURL;
@end
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
@end

static BOOL RBNormalApplication(LSApplicationProxy *app) {
    if ([app respondsToSelector:@selector(isInstalled)] && !app.isInstalled) return NO;
    if ([app respondsToSelector:@selector(isPlaceholder)] && app.isPlaceholder) return NO;
    if ([app respondsToSelector:@selector(isLaunchProhibited)] && app.isLaunchProhibited) return NO;
    NSURL *url = [app respondsToSelector:@selector(bundleURL)] ? app.bundleURL : nil;
    if (url) {
        if (![url.pathExtension.lowercaseString isEqualToString:@"app"]) return NO;
        id info = [NSDictionary dictionaryWithContentsOfURL:[url URLByAppendingPathComponent:@"Info.plist"]];
        if (info && ![info isKindOfClass:[NSDictionary class]]) return NO;
        if (info[@"NSExtension"]) return NO;
        for (NSString *key in @[@"LSUIElement", @"LSBackgroundOnly"]) {
            id flag = info[key];
            if (flag && ![flag isKindOfClass:[NSNumber class]]) return NO;
            if ([flag boolValue]) return NO;
        }
        NSString *type = info[@"CFBundlePackageType"];
        if (type && (![type isKindOfClass:NSString.class] || ![type isEqualToString:@"APPL"])) return NO;
        id tags = info[@"SBAppTags"];
        if ([tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"]) return NO;
    }
    return YES;
}

NSArray<NSDictionary *> *RBInstalledApplications(void) {
    @try {
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    LSApplicationWorkspace *workspace = [cls respondsToSelector:@selector(defaultWorkspace)]
        ? [cls defaultWorkspace] : nil;
    if (![workspace respondsToSelector:@selector(allInstalledApplications)]) return nil;
    NSArray *installed = [workspace allInstalledApplications];
    if (![installed isKindOfClass:[NSArray class]]) return nil;

    NSMutableArray<NSDictionary *> *apps = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSNumber *> *nameCounts = [NSMutableDictionary dictionary];
    for (LSApplicationProxy *app in installed) {
        if (![app respondsToSelector:@selector(applicationIdentifier)]) continue;
        NSString *appID = app.applicationIdentifier;
        if (![appID isKindOfClass:[NSString class]] || !appID.length || [seen containsObject:appID] ||
            [appID isEqualToString:@"com.apple.springboard"] || !RBNormalApplication(app)) continue;
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
    for (NSUInteger index = 0; index < apps.count; index++) {
        NSDictionary *app = apps[index];
        if ([nameCounts[app[@"name"]] unsignedIntegerValue] > 1) {
            NSMutableDictionary *withSubtitle = [app mutableCopy];
            withSubtitle[@"subtitle"] = app[@"id"];
            apps[index] = withSubtitle;
        }
    }
    return apps;
    } @catch (NSException *exception) {
        (void)exception;
        return nil;
    }
}

NSArray<NSDictionary *> *RBFilterApplications(NSArray<NSDictionary *> *applications, NSString *query) {
    NSString *needle = [[query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        precomposedStringWithCanonicalMapping];
    if (!needle.length) return applications;
    NSPredicate *matching = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *app, NSDictionary *bindings) {
        return [app[@"name"] localizedCaseInsensitiveContainsString:needle] ||
            [app[@"id"] localizedCaseInsensitiveContainsString:needle];
    }];
    return [applications filteredArrayUsingPredicate:matching];
}
