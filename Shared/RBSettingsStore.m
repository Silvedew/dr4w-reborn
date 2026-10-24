#import "RBSettings.h"
#import "RBDiagnostics.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

// The bridge cannot choose a domain or touch files. Only drawing values are writable.
static BOOL RBWritableDrawingKey(NSString *key, id value) {
    if (![key isKindOfClass:NSString.class]) return NO;
    NSArray *keys = @[@"toolIndex", @"colorIndex", @"hasCustom", @"cR", @"cG", @"cB", @"cA",
        @"widthIndex", @"strokeWidth", @"floatX", @"floatY", @"ballSize", @"ballAlpha"];
    if ([key isEqual:@"strokeWidth"] && value && (![value isKindOfClass:NSNumber.class] ||
        [value doubleValue] < 1 || [value doubleValue] > 30 || round([value doubleValue]) != [value doubleValue])) return NO;
    return [keys containsObject:key] && (!value ||
        ([value isKindOfClass:NSNumber.class] && isfinite([value doubleValue])));
}

static NSArray<NSString *> *RBServiceNames(void) {
    return @[[ @"cy:" stringByAppendingString:[RB_SETTINGS_DOMAIN stringByAppendingString:@".settings"]],
             [ @"lh:" stringByAppendingString:[RB_SETTINGS_DOMAIN stringByAppendingString:@".settings"]]];
}

static NSData *RBEncode(id value) {
    return value ? [NSPropertyListSerialization dataWithPropertyList:value
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL] : nil;
}

static NSDictionary *RBDecode(NSData *data) {
    if (!data.length || data.length > 256 * 1024) return nil;
    id value = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
        format:NULL error:NULL];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSDictionary *RBHandleSettingsRequest(NSDictionary *request) {
    if (![request[@"domain"] isEqual:RB_SETTINGS_DOMAIN]) return nil;
    NSString *operation = request[@"operation"];
    if ([operation isEqual:@"read"] && request.count == 2) {
        NSDictionary *values = RBPreferences().dictionaryRepresentation;
        return values ? @{@"values": values} : nil;
    }
    BOOL remove = [operation isEqual:@"remove"];
    if ((remove || [operation isEqual:@"write"]) && request.count == (remove ? 3 : 4) &&
        RBWritableDrawingKey(request[@"key"], request[@"value"]) && (remove || request[@"value"])) {
        [RBPreferences() setObject:remove ? nil : request[@"value"] forKey:request[@"key"]];
        RBSignalSettingsChanged();
        return @{@"saved": @YES};
    }
    return nil;
}

static CFDataRef RBReceiveSettings(CFMessagePortRef port, SInt32 message, CFDataRef data, void *info) {
    @autoreleasepool {
        if (message != 1) return NULL;
        NSDictionary *request = RBDecode((__bridge NSData *)data);
        return CFBridgingRetain(RBEncode(request ? RBHandleSettingsRequest(request) : nil));
    }
}

void RBStartSettingsService(void) {
    NSCAssert(NSThread.isMainThread, @"Register settings service on the main thread");
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *name in RBServiceNames()) {
            CFMessagePortRef port = CFMessagePortCreateLocal(NULL, (__bridge CFStringRef)name,
                RBReceiveSettings, NULL, NULL);
            RBDiagnostic(@"settings.service", [NSString stringWithFormat:@"name=%@ registered=%d", name, port != NULL]);
            if (!port) continue;
            CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(NULL, port, 0);
            if (source) {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
                CFRelease(source);
            }
            CFRelease(port); // The run-loop source retains the local service.
        }
        RBSignalSettingsChanged(); // Wake already-running clients after SpringBoard registers.
    });
}

static NSDictionary *RBBridgeRequest(NSDictionary *request) {
    NSData *data = RBEncode(request);
    for (NSString *name in RBServiceNames()) {
        CFMessagePortRef port = CFMessagePortCreateRemote(NULL, (__bridge CFStringRef)name);
        if (!port) {
            RBDiagnostic(@"settings.lookup", [NSString stringWithFormat:@"name=%@ available=0", name]);
            continue;
        }
        CFDataRef reply = NULL;
        SInt32 result = CFMessagePortSendRequest(port, 1, (__bridge CFDataRef)data,
            0.15, 0.25, kCFRunLoopDefaultMode, &reply);
        CFRelease(port);
        NSDictionary *response = RBDecode(CFBridgingRelease(reply));
        RBDiagnostic(@"settings.transport", [NSString stringWithFormat:@"name=%@ result=%d valid=%d",
            name, (int)result, response != nil]);
        if (result == kCFMessagePortSuccess && response) return response;
    }
    return nil;
}

static BOOL RBSandboxPreferences(void) {
    // HBPreferences explicitly substitutes its IPC subclass in sandboxed apps.
    return [RBPreferences() isKindOfClass:NSClassFromString(@"HBPreferencesIPC")];
}

static dispatch_queue_t RBSettingsQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.dsh.dr4wreborn.settings", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

// Cephei's own transport has no caller-controlled timeout. Never let it hold up
// the bridge queue, and never spawn more than one outstanding Cephei read.
static dispatch_group_t gCepheiRead;
static NSDictionary *gCepheiResult;
static NSDictionary *RBReadCephei(void) {
    if (!gCepheiRead) {
        gCepheiRead = dispatch_group_create();
        dispatch_group_async(gCepheiRead, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            gCepheiResult = RBPreferences().dictionaryRepresentation;
        });
    }
    if (dispatch_group_wait(gCepheiRead, dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC)) != 0)
        return nil;
    NSDictionary *result = gCepheiResult;
    gCepheiRead = nil;
    return result;
}

static NSDictionary *gSnapshot;
static NSMutableArray *gSettingsObservers;
static BOOL gRefreshPending;
static BOOL gRefreshAgain;

id RBSnapshotValue(NSString *key) {
    // Privileged processes use Cephei's local cache; app layout never performs IPC.
    return RBSandboxPreferences() ? gSnapshot[key] : [RBPreferences() objectForKey:key];
}

static void RBPublishSettings(void) {
    for (void (^callback)(void) in [gSettingsObservers copy]) callback();
}

void RBRefreshSettings(void) {
    if (!RBSandboxPreferences()) return;
    if (gRefreshPending) { gRefreshAgain = YES; return; }
    gRefreshPending = YES;
    dispatch_async(RBSettingsQueue(), ^{
        NSDictionary *values = RBReadCephei();
        NSString *backend = @"Cephei";
        if (!values) {
            values = RBBridgeRequest(@{@"domain": RB_SETTINGS_DOMAIN, @"operation": @"read"})[@"values"];
            backend = @"bridge";
        }
        BOOL valid = [values isKindOfClass:NSDictionary.class];
        NSDictionary *snapshot = valid ? [values copy] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            gRefreshPending = NO;
            // A transport failure must not overwrite the last successful configuration.
            if (snapshot) gSnapshot = snapshot;
            RBDiagnostic(@"settings.snapshot", [NSString stringWithFormat:@"backend=%@ success=%d keys=%lu retained=%d",
                backend, valid, (unsigned long)gSnapshot.count, !valid && gSnapshot != nil]);
            RBPublishSettings();
            if (gRefreshAgain) { gRefreshAgain = NO; RBRefreshSettings(); }
        });
    });
}

void RBObserveSnapshot(void (^callback)(void)) {
    if (!gSettingsObservers) gSettingsObservers = [NSMutableArray array];
    [gSettingsObservers addObject:[callback copy]];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [RBPreferences() registerPreferenceChangeBlock:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (RBSandboxPreferences()) RBRefreshSettings();
                else RBPublishSettings();
            });
        }];
    });
    dispatch_async(dispatch_get_main_queue(), callback);
}

BOOL RBStoreSetting(NSString *key, id value) {
    if (!RBSandboxPreferences()) {
        [RBPreferences() setObject:value forKey:key];
        return RBSignalSettingsChanged();
    }
    if (!RBWritableDrawingKey(key, value)) return NO;
    NSMutableDictionary *updated = [gSnapshot mutableCopy] ?: [NSMutableDictionary dictionary];
    updated[key] = value;
    gSnapshot = updated;
    dispatch_async(RBSettingsQueue(), ^{
        // App writes always use the bounded bridge: Cephei's void setter cannot
        // acknowledge failures or enforce a deadline. Settings still writes locally.
        NSMutableDictionary *request = [@{@"domain": RB_SETTINGS_DOMAIN,
            @"operation": value ? @"write" : @"remove", @"key": key} mutableCopy];
        if (value) request[@"value"] = value;
        BOOL saved = [RBBridgeRequest(request)[@"saved"] boolValue];
        RBDiagnostic(@"settings.write", saved ? @"saved=1" : @"saved=0");
        dispatch_async(dispatch_get_main_queue(), ^{ RBRefreshSettings(); });
    });
    return YES; // Accepted asynchronously; persistence failures are reported in diagnostics.
}
