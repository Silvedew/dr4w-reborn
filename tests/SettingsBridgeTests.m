// Real CFMessagePort transport between two processes; Cephei failure is simulated.
#import <Foundation/Foundation.h>
static NSString *gTestDomain;
#define RB_SETTINGS_DOMAIN gTestDomain
#import "RBSettings.h"
#import "RBAppCatalog.h"
#include <assert.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>

static BOOL gCepheiHealthy;
static NSMutableDictionary *gCepheiValues;
static void (^gCepheiCallback)(void);
static dispatch_semaphore_t gCepheiStallGate;
@interface HBPreferencesIPC : HBPreferences
@end
@implementation HBPreferencesIPC
- (NSDictionary *)dictionaryRepresentation {
    dispatch_semaphore_t gate = gCepheiStallGate;
    if (gate) dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
    return gCepheiHealthy ? [gCepheiValues copy] : nil;
}
- (id)objectForKey:(NSString *)key { assert(!"App reads must use the snapshot"); return nil; }
- (void)setObject:(id)value forKey:(NSString *)key { assert(gCepheiHealthy); gCepheiValues[key] = value; }
- (void)registerPreferenceChangeBlock:(void (^)(void))callback { gCepheiCallback = [callback copy]; callback(); }
@end

static HBPreferences *gClientPreferences;
static BOOL gCatalogUnavailable;
static BOOL gCatalogThrows;
static NSArray<NSDictionary *> *RBFixtureInstalledApplications(void) {
    if (gCatalogThrows) [NSException raise:@"RBFixtureCatalogFailure" format:@"simulated enumeration failure"];
    if (gCatalogUnavailable) return nil;
    NSMutableArray *apps = [NSMutableArray array];
    for (NSString *bundleID in @[@"tv.danmaku.bilianime", @"test.reader", @"test.other",
        @"test.concurrent.a", @"test.concurrent.b"])
        [apps addObject:@{@"id":bundleID, @"name":bundleID}];
    return apps;
}
@interface RBFailingPreferences : HBPreferences
@end
@implementation RBFailingPreferences
- (id)objectForKey:(NSString *)key { return [RBPreferences() objectForKey:key]; }
- (NSDictionary *)dictionaryRepresentation { return RBPreferences().dictionaryRepresentation; }
- (void)setObject:(id)value forKey:(NSString *)key {
    [NSException raise:@"RBFixtureWriteFailure" format:@"simulated persistence failure"];
}
@end
@interface RBSilentPreferences : RBFailingPreferences
@end
@implementation RBSilentPreferences
- (void)setObject:(id)value forKey:(NSString *)key { }
@end
static HBPreferences *RBTestPreferences(void) { return gClientPreferences ?: RBPreferences(); }
#define RBPreferences RBTestPreferences
#define RBInstalledApplications RBFixtureInstalledApplications
#import "../Shared/RBSettingsStore.m"
#undef RBPreferences
#undef RBInstalledApplications

static CFDataRef RBReceiveDroppingAppAck(CFMessagePortRef port, SInt32 message, CFDataRef data, void *info) {
    CFDataRef reply = RBReceiveSettings(port, message, data, info);
    NSDictionary *request = RBDecode((__bridge NSData *)data);
    if ([request[@"operation"] isEqual:@"appEnabled"]) {
        assert([RBDecode((__bridge NSData *)reply)[@"saved"] boolValue]);
        if (reply) CFRelease(reply);
        return NULL;
    }
    return reply;
}

static void PumpUntil(BOOL (^condition)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && limit.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(condition());
}

static void Refresh(void) {
    RBReloadSettings();
    PumpUntil(^BOOL { return !gRefreshPending; });
}

static NSTask *StartServer(NSString *mode) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];
    task.arguments = @[mode, gTestDomain];
    NSPipe *output = [NSPipe pipe];
    task.standardOutput = output;
    __block BOOL ready = NO;
    output.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (data.length) dispatch_async(dispatch_get_main_queue(), ^{ ready = YES; });
    };
    assert([task launchAndReturnError:NULL]);
    PumpUntil(^BOOL { return ready; });
    output.fileHandleForReading.readabilityHandler = nil;
    return task;
}

static NSDictionary *Request(NSString *operation) {
    return @{@"domain": gTestDomain, @"operation": operation};
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1) {
            gTestDomain = @(argv[2]);
            if (strcmp(argv[1], "--verify-position") == 0) {
                RBToolbarPosition position = RBToolbarPositionForApp(@"test.reader");
                assert(position.x == 0.2 && position.y == 0.8);
                position = RBToolbarPositionForApp(@"test.other");
                assert(position.x == 0.7 && position.y == 0.3);
                assert(([RBBrushColorForSlot(0) isEqual:@[@0.1,@0.2,@0.3,@1]]));
                assert(([RBBrushColorForSlot(1) isEqual:@[@0.8,@0.4,@0.1,@1]]));
                assert([RBSetting(@"toolbarScale", nil) doubleValue] == 1.5);
                assert([RBSetting(@"enabledApps", @[]) containsObject:@"test.concurrent.a"]);
                assert([RBSetting(@"enabledApps", @[]) containsObject:@"test.concurrent.b"]);
                assert(![RBSetting(@"enabledApps", @[]) containsObject:@"test.reader"]);
                return 0;
            }
            if (![RBPreferences() objectForKey:@"enabledApps"])
                [RBPreferences() setObject:@[@"tv.danmaku.bilianime"] forKey:@"enabledApps"];
            [RBPreferences() setObject:@3 forKey:@"colorIndex"];
            gCatalogUnavailable = strcmp(argv[1], "--catalog-unavailable") == 0;
            if (strcmp(argv[1], "--write-fails") == 0) gClientPreferences = [RBFailingPreferences new];
            if (strcmp(argv[1], "--write-silent") == 0) gClientPreferences = [RBSilentPreferences new];
            BOOL dropAcknowledgement = strcmp(argv[1], "--lost-app-ack") == 0;
            if (strcmp(argv[1], "--lh-only") == 0 || dropAcknowledgement) {
                NSArray *names = dropAcknowledgement ? RBServiceNames() : @[RBServiceNames()[1]];
                for (NSString *name in names) {
                    CFMessagePortRef port = CFMessagePortCreateLocal(NULL, (__bridge CFStringRef)name,
                        dropAcknowledgement ? RBReceiveDroppingAppAck : RBReceiveSettings, NULL, NULL);
                    assert(port);
                    CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(NULL, port, 0);
                    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
                    CFRelease(source);
                    CFRelease(port);
                }
            } else RBStartSettingsService();
            printf("ready\n"); fflush(stdout);
            if (strcmp(argv[1], "--stalled") == 0) [NSThread sleepForTimeInterval:30];
            else [[NSRunLoop currentRunLoop] run];
            return 0;
        }
        // A failed enumeration must clear loading so a later request can recover.
        gCatalogThrows = YES;
        RBRefreshApplicationCatalog();
        PumpUntil(^BOOL { return !gApplicationCatalogLoading; });
        assert(!gApplicationCatalog);
        gCatalogThrows = NO;
        RBRefreshApplicationCatalog();
        PumpUntil(^BOOL { return !gApplicationCatalogLoading; });
        assert(gApplicationCatalog.count == 5);
        gApplicationCatalog = nil;

        gTestDomain = [NSString stringWithFormat:@"com.dsh.dr4wreborn.bridge-tests.%d", getpid()];
        NSTask *server = StartServer(@"--server");
        NSDictionary *response = RBBridgeRequest(Request(@"read"));
        assert([response[@"values"][@"colorIndex"] isEqual:@3]);
        // Generic writes cannot replace app policy, choose domains, or access paths.
        assert(!RBBridgeRequest(@{@"domain": @"com.apple.test", @"operation": @"read"}));
        assert(!RBBridgeRequest(@{@"domain": gTestDomain, @"operation": @"write",
            @"key": @"enabledApps", @"value": @[]}));
        assert(!RBBridgeRequest(@{@"domain": gTestDomain, @"operation": @"write",
            @"key": @"floatX", @"value": @"/var/mobile/test"}));
        assert(!RBDecode([NSMutableData dataWithLength:256 * 1024 + 1]));
        assert(!RBDecode([@"invalid" dataUsingEncoding:NSUTF8StringEncoding]));
        assert(!RBWritableDrawingKey(@"floatX", @(NAN)));
        assert(!RBWritableDrawingKey(@"strokeWidth", @0));
        assert(!RBWritableDrawingKey(@"strokeWidth", @31));
        assert(!RBWritableDrawingKey(@"strokeWidth", @1.5));
        for (id invalid in @[@0.59, @1.51, @(NAN), @(INFINITY), @"1.0"])
            assert(!RBWritableDrawingKey(@"toolbarScale", invalid));
        assert(!RBBridgeRequest(@{@"domain":gTestDomain, @"operation":@"appEnabled",
            @"bundle":@"../file", @"enabled":@YES}));
        assert(!RBBridgeRequest(@{@"domain":gTestDomain, @"operation":@"appEnabled",
            @"bundle":@"com.apple.springboard", @"enabled":@NO}));
        assert(!RBBridgeRequest(@{@"domain":gTestDomain, @"operation":@"appEnabled",
            @"bundle":@"test.reader", @"enabled":@2}));
        assert(!RBBridgeRequest(@{@"domain":gTestDomain, @"operation":@"applications", @"refresh":@"yes"}));
        assert(!RBHandleSettingsRequest(@{@"domain": gTestDomain, @"operation": @7}));
        assert(!RBBridgeRequest(@{@"domain": gTestDomain, @"operation": @"write",
            @"key": @"toolbarPositions", @"value": @{}}));
        assert(!RBBridgeRequest(@{@"domain": gTestDomain, @"operation": @"write",
            @"key": @"brushColors", @"value": @{}}));
        assert(!RBBridgeRequest(@{@"domain": gTestDomain, @"operation": @"brushColor", @"slot":@4,
            @"rgba":@[@0,@0,@0,@1]}));
        assert(!RBBridgeRequest(@{@"domain": gTestDomain, @"operation": @"brushColor", @"slot":@0,
            @"rgba":@[@0,@2,@0,@1]}));
        assert(!RBBridgeRequest(@{@"domain": gTestDomain, @"operation": @"toolbarPosition",
            @"bundle": @"test.reader", @"x": @1.1, @"y": @0.2}));
        assert(!RBBridgeRequest(@{@"domain": gTestDomain, @"operation": @"toolbarPosition",
            @"bundle": @"../../file", @"x": @0.1, @"y": @0.2}));

        gClientPreferences = [HBPreferencesIPC new];
        __block NSUInteger callbacks = 0;
        RBObserveSettings(^{ callbacks++; });
        Refresh();
        assert(RBEnabledForBundle(@"tv.danmaku.bilianime"));
        assert(RBBallForBundle(@"tv.danmaku.bilianime"));
        assert([RBSetting(@"colorIndex", nil) isEqual:@3]);
        assert(callbacks > 0);
        assert(RBWriteSetting(@"colorIndex", @5));
        assert([RBSetting(@"colorIndex", nil) isEqual:@5]);
        PumpUntil(^BOOL {
            return [RBBridgeRequest(Request(@"read"))[@"values"][@"colorIndex"] isEqual:@5];
        });
        assert(!RBWriteSetting(@"enabled", @NO));
        assert(!RBWriteSetting(@"enabledApps", @[]));
        __block BOOL loaded = NO;
        RBLoadApplications(^(NSArray<NSDictionary *> *apps, NSError *error) {
            assert(NSThread.isMainThread && !error && apps.count == 5);
            loaded = YES;
        });
        PumpUntil(^BOOL { return loaded; });
        __block BOOL enabledApp = NO;
        RBSetAppEnabled(@"test.reader", YES, ^(BOOL saved, NSError *error) {
            assert(NSThread.isMainThread && saved && !error);
            assert([RBSetting(@"enabledApps", @[]) containsObject:@"test.reader"]);
            assert([RBSetting(@"enabledApps", @[]) containsObject:@"tv.danmaku.bilianime"]);
            enabledApp = YES;
        });
        PumpUntil(^BOOL { return enabledApp; });
        assert(![RBBridgeRequest(@{@"domain":gTestDomain, @"operation":@"appEnabled",
            @"bundle":@"test.not-installed", @"enabled":@YES})[@"saved"] boolValue]);
        __block BOOL disabledApp = NO;
        RBSetAppEnabled(@"test.reader", NO, ^(BOOL saved, NSError *error) {
            assert(saved && !error && ![RBSetting(@"enabledApps", @[]) containsObject:@"test.reader"]);
            disabledApp = YES;
        });
        PumpUntil(^BOOL { return disabledApp; });
        __block NSUInteger appChanges = 0;
        for (NSString *bundleID in @[@"test.concurrent.a", @"test.concurrent.b"])
            RBSetAppEnabled(bundleID, YES, ^(BOOL saved, NSError *error) {
                assert(saved && !error);
                appChanges++;
            });
        PumpUntil(^BOOL { return appChanges == 2; });
        NSArray *enabledApps = RBBridgeRequest(Request(@"read"))[@"values"][@"enabledApps"];
        assert(enabledApps.count == 3 && [enabledApps containsObject:@"test.concurrent.a"] &&
            [enabledApps containsObject:@"test.concurrent.b"]);
        assert(RBWriteSetting(@"toolbarScale", @0.6));
        assert(RBWriteSetting(@"toolbarScale", @1.5));
        PumpUntil(^BOOL {
            return [RBBridgeRequest(Request(@"read"))[@"values"][@"toolbarScale"] isEqual:@1.5];
        });
        assert(RBSaveBrushColor(0, @[@0.1,@0.2,@0.3,@1]));
        assert(RBSaveBrushColor(1, @[@0.8,@0.4,@0.1,@1]));
        assert(([RBBrushColorForSlot(0) isEqual:@[@0.1,@0.2,@0.3,@1]]));
        assert(RBSelectedBrushSlot() == 1);
        PumpUntil(^BOOL {
            NSDictionary *values = RBBridgeRequest(Request(@"read"))[@"values"];
            return [values[@"brushColors"][@"1"] isEqual:@[@0.8,@0.4,@0.1,@1]] && [values[@"cR"] isEqual:@0.8];
        });
        assert([RBBridgeRequest(@{@"domain":gTestDomain, @"operation":@"brushColor", @"slot":@2,
            @"rgba":@[@0.5,@0.6,@0.7,@1]})[@"saved"] boolValue]);
        assert([RBBridgeRequest(Request(@"read"))[@"values"][@"brushColors"] count] == 3);
        assert(RBWriteSetting(@"strokeWidth", @17));
        PumpUntil(^BOOL {
            return [RBBridgeRequest(Request(@"read"))[@"values"][@"strokeWidth"] isEqual:@17];
        });
        assert(RBSaveToolbarPosition(@"test.reader", (RBToolbarPosition){0.2,0.8}));
        assert(RBSaveToolbarPosition(@"test.other", (RBToolbarPosition){0.7,0.3}));
        assert(RBToolbarPositionForApp(@"test.reader").x == 0.2); // Immediate reopen before acknowledgment.
        PumpUntil(^BOOL {
            NSDictionary *positions = RBBridgeRequest(Request(@"read"))[@"values"][@"toolbarPositions"];
            return [positions[@"test.reader"][@"y"] isEqual:@0.8] && [positions[@"test.other"][@"x"] isEqual:@0.7];
        });
        dispatch_group_t writers = dispatch_group_create();
        for (NSString *bundle in @[@"test.concurrent.a", @"test.concurrent.b"]) {
            dispatch_group_async(writers, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                assert([RBBridgeRequest(@{@"domain": gTestDomain, @"operation": @"toolbarPosition",
                    @"bundle": bundle, @"x": @0.4, @"y": @0.6})[@"saved"] boolValue]);
            });
        }
        assert(dispatch_group_wait(writers, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0);
        NSDictionary *positions = RBBridgeRequest(Request(@"read"))[@"values"][@"toolbarPositions"];
        assert(positions.count == 4 && positions[@"test.concurrent.a"] && positions[@"test.concurrent.b"]);
        NSTask *verifier = [NSTask new];
        verifier.executableURL = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];
        verifier.arguments = @[@"--verify-position", gTestDomain];
        assert([verifier launchAndReturnError:NULL]);
        [verifier waitUntilExit];
        assert(verifier.terminationStatus == 0); // A fresh process reads the persisted, per-app positions.
        [server terminate]; [server waitUntilExit];
        server = StartServer(@"--server");
        positions = RBBridgeRequest(Request(@"read"))[@"values"][@"toolbarPositions"];
        assert(positions.count == 4); // SpringBoard/server restart retains all apps.
        assert([RBBridgeRequest(Request(@"read"))[@"values"][@"brushColors"] count] == 3);

        // Healthy Cephei takes precedence, including a successfully empty configuration.
        gCepheiHealthy = YES;
        gCepheiValues = [@{@"enabledApps": @[@"test.other"]} mutableCopy];
        Refresh();
        assert(!RBBallForBundle(@"tv.danmaku.bilianime"));
        assert(RBBallForBundle(@"test.other"));
        gCepheiValues[@"enabledApps"] = @[];
        gCepheiCallback();
        PumpUntil(^BOOL { return !RBBallForBundle(@"test.other"); });
        [gCepheiValues removeAllObjects];
        Refresh();
        assert(gSnapshot && gSnapshot.count == 0);
        assert(!RBBallForBundle(@"tv.danmaku.bilianime"));

        // A new foreground entry recovers from a previously unavailable Cephei service.
        gCepheiHealthy = NO;
        Refresh();
        assert(RBBallForBundle(@"tv.danmaku.bilianime"));
        // A hung Cephei read must not prevent the healthy bridge from being used.
        gCepheiStallGate = dispatch_semaphore_create(0);
        NSDate *cepheiStart = [NSDate date];
        Refresh();
        assert(-cepheiStart.timeIntervalSinceNow < 2.0);
        assert(gCepheiRead && RBBallForBundle(@"tv.danmaku.bilianime"));
        dispatch_semaphore_t gate = gCepheiStallGate;
        gCepheiStallGate = nil;
        dispatch_semaphore_signal(gate);
        Refresh();
        [server terminate]; [server waitUntilExit];
        Refresh();
        assert(RBBallForBundle(@"tv.danmaku.bilianime")); // Failed read retains last snapshot.
        assert(RBSaveToolbarPosition(@"test.reader", (RBToolbarPosition){0.3,0.6}));
        assert(RBToolbarPositionForApp(@"test.reader").x == 0.3); // Failed save keeps current UI position.
        gSnapshot = nil;
        Refresh();
        assert(!gSnapshot && !RBBallForBundle(@"tv.danmaku.bilianime"));

        gTestDomain = [gTestDomain stringByAppendingString:@".lh"];
        server = StartServer(@"--lh-only");
        Refresh();
        assert(RBBallForBundle(@"tv.danmaku.bilianime"));
        [server terminate]; [server waitUntilExit];

        // An unresponsive service times out off-main; the main run loop keeps ticking.
        gTestDomain = [gTestDomain stringByAppendingString:@".timeout"];
        server = StartServer(@"--stalled");
        __block NSUInteger ticks = 0;
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES
            block:^(NSTimer *t) { ticks++; }];
        NSDate *start = [NSDate date];
        Refresh();
        assert(ticks >= 5 && -start.timeIntervalSinceNow < 2.0);
        assert(RBBallForBundle(@"tv.danmaku.bilianime"));
        NSDictionary *beforeTimeout = [gSnapshot copy];
        __block BOOL appTimedOut = NO;
        RBSetAppEnabled(@"test.reader", YES, ^(BOOL saved, NSError *error) {
            assert(NSThread.isMainThread && !saved && error);
            assert([gSnapshot isEqual:beforeTimeout]);
            appTimedOut = YES;
        });
        PumpUntil(^BOOL { return appTimedOut; });
        assert([gSnapshot isEqual:beforeTimeout]);
        [timer invalidate];
        [server terminate]; [server waitUntilExit];

        gTestDomain = [gTestDomain stringByAppendingString:@".catalog-failure"];
        server = StartServer(@"--catalog-unavailable");
        __block BOOL failedCatalog = NO;
        RBLoadApplications(^(NSArray<NSDictionary *> *apps, NSError *error) {
            assert(NSThread.isMainThread && !apps && error);
            failedCatalog = YES;
        });
        PumpUntil(^BOOL { return failedCatalog; });
        [server terminate]; [server waitUntilExit];

        gTestDomain = [gTestDomain stringByAppendingString:@".write-failure"];
        server = StartServer(@"--write-fails");
        __block BOOL failedWrite = NO;
        RBSetAppEnabled(@"test.reader", YES, ^(BOOL saved, NSError *error) {
            assert(NSThread.isMainThread && !saved && error);
            assert(![RBSetting(@"enabledApps", @[]) containsObject:@"test.reader"]);
            failedWrite = YES;
        });
        PumpUntil(^BOOL { return failedWrite; });
        [server terminate]; [server waitUntilExit];

        gTestDomain = [gTestDomain stringByAppendingString:@".silent-write"];
        server = StartServer(@"--write-silent");
        __block BOOL silentWriteRejected = NO;
        RBSetAppEnabled(@"test.reader", YES, ^(BOOL saved, NSError *error) {
            assert(NSThread.isMainThread && !saved && error);
            assert(![RBSetting(@"enabledApps", @[]) containsObject:@"test.reader"]);
            silentWriteRejected = YES;
        });
        PumpUntil(^BOOL { return silentWriteRejected; });
        response = RBBridgeRequest(@{@"domain":gTestDomain, @"operation":@"appEnabled",
            @"bundle":@"test.reader", @"enabled":@YES});
        assert(response && ![response[@"saved"] boolValue]);
        assert(![response[@"enabledApps"] containsObject:@"test.reader"]);
        [server terminate]; [server waitUntilExit];

        gTestDomain = [gTestDomain stringByAppendingString:@".lost-ack"];
        server = StartServer(@"--lost-app-ack");
        __block BOOL recoveredWrite = NO;
        RBSetAppEnabled(@"test.reader", YES, ^(BOOL saved, NSError *error) {
            assert(NSThread.isMainThread && saved && !error);
            assert([RBSetting(@"enabledApps", @[]) containsObject:@"test.reader"]);
            recoveredWrite = YES;
        });
        PumpUntil(^BOOL { return recoveredWrite; });
        assert([RBBridgeRequest(Request(@"read"))[@"values"][@"enabledApps"] containsObject:@"test.reader"]);
        [server terminate]; [server waitUntilExit];
        NSLog(@"Cephei precedence, sandbox fallback, cy/lh transport, validation, snapshot retention and timeout passed.");
    }
    return 0;
}
