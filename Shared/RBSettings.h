#pragma once
#import <Foundation/Foundation.h>
#import <Cephei/HBPreferences.h>
#import <notify.h>
#import "RBPolicy.h"

#ifndef RB_SETTINGS_DOMAIN
#define RB_SETTINGS_DOMAIN @"com.dsh.dr4wreborn"
#endif
#define RB_SETTINGS_CHANGED "com.dsh.dr4wreborn.settingschanged"

static inline HBPreferences *RBPreferences(void) {
    static HBPreferences *preferences;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ preferences = [HBPreferences preferencesForIdentifier:RB_SETTINGS_DOMAIN]; });
    return preferences;
}

static inline id RBSetting(NSString *key, id fallback) {
    return [RBPreferences() objectForKey:key] ?: fallback;
}

static inline BOOL RBSettingBool(NSString *key, BOOL fallback) {
    id value = RBSetting(key, @(fallback));
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

static inline void RBReloadSettings(void) {
    // Cephei 2 reloads its cache before delivering preference-change callbacks.
    (void)RBPreferences();
}

static inline BOOL RBSignalSettingsChanged(void) {
    NSString *notification = [RB_SETTINGS_DOMAIN stringByAppendingString:@"/ReloadPrefs"];
    BOOL posted = notify_post(notification.UTF8String) == NOTIFY_STATUS_OK;
    if (posted) notify_post(RB_SETTINGS_CHANGED);
    return posted;
}

static inline BOOL RBWriteSetting(NSString *key, id value) {
    @try {
        [RBPreferences() setObject:value forKey:key];
        return RBSignalSettingsChanged();
    } @catch (NSException *exception) {
        NSLog(@"[Dr4wReborn] preference write failed: %@", exception.name);
        return NO;
    }
}

static inline void RBObserveSettings(void (^callback)(void)) {
    [RBPreferences() registerPreferenceChangeBlock:^{
        dispatch_async(dispatch_get_main_queue(), callback);
    }];
}

static inline BOOL RBEnabledForBundle(NSString *bundleID) {
    if (!bundleID.length) return NO;
    id apps = RBSetting(@"enabledApps", @[]);
    BOOL selected = [apps isKindOfClass:[NSArray class]] && [apps containsObject:bundleID];
    return RBPolicyEnabled(RBSettingBool(@"enabled", YES), RBSettingBool(@"homeEnabled", YES),
        selected, [bundleID isEqualToString:@"com.apple.springboard"]);
}

static inline BOOL RBBallForBundle(NSString *bundleID) {
    return RBEnabledForBundle(bundleID);
}
