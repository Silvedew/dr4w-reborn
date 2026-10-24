// Real CFMessagePort transport between two processes; Cephei failure is simulated.
#import <Foundation/Foundation.h>
static NSString *gTestDomain;
#define RB_SETTINGS_DOMAIN gTestDomain
#import "RBSettings.h"
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
static HBPreferences *RBTestPreferences(void) { return gClientPreferences ?: RBPreferences(); }
#define RBPreferences RBTestPreferences
#import "../Shared/RBSettingsStore.m"
#undef RBPreferences

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
            [RBPreferences() setObject:@[@"tv.danmaku.bilianime"] forKey:@"enabledApps"];
            [RBPreferences() setObject:@3 forKey:@"colorIndex"];
            if (strcmp(argv[1], "--lh-only") == 0) {
                CFMessagePortRef port = CFMessagePortCreateLocal(NULL,
                    (__bridge CFStringRef)RBServiceNames()[1], RBReceiveSettings, NULL, NULL);
                assert(port);
                CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(NULL, port, 0);
                CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
                CFRelease(source);
                CFRelease(port);
            } else RBStartSettingsService();
            printf("ready\n"); fflush(stdout);
            if (strcmp(argv[1], "--stalled") == 0) [NSThread sleepForTimeInterval:30];
            else [[NSRunLoop currentRunLoop] run];
            return 0;
        }
        gTestDomain = [NSString stringWithFormat:@"com.dsh.dr4wreborn.bridge-tests.%d", getpid()];
        NSTask *server = StartServer(@"--server");
        NSDictionary *response = RBBridgeRequest(Request(@"read"));
        assert([response[@"values"][@"colorIndex"] isEqual:@3]);
        // Untrusted requests cannot change app policy, choose domains, or access paths.
        assert(!RBBridgeRequest(@{@"domain": @"com.apple.test", @"operation": @"read"}));
        assert(!RBBridgeRequest(@{@"domain": gTestDomain, @"operation": @"write",
            @"key": @"enabledApps", @"value": @[]}));
        assert(!RBBridgeRequest(@{@"domain": gTestDomain, @"operation": @"write",
            @"key": @"floatX", @"value": @"/var/mobile/test"}));
        assert(!RBDecode([NSMutableData dataWithLength:256 * 1024 + 1]));
        assert(!RBDecode([@"invalid" dataUsingEncoding:NSUTF8StringEncoding]));
        assert(!RBWritableDrawingKey(@"floatX", @(NAN)));
        assert(!RBHandleSettingsRequest(@{@"domain": gTestDomain, @"operation": @7}));

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
        [timer invalidate];
        [server terminate]; [server waitUntilExit];
        NSLog(@"Cephei precedence, sandbox fallback, cy/lh transport, validation, snapshot retention and timeout passed.");
    }
    return 0;
}
