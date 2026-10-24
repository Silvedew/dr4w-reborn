#pragma once
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import "RBPolicy.h"

#ifndef RB_SETTINGS_DOMAIN
#define RB_SETTINGS_DOMAIN @"com.dsh.dr4wreborn"
#endif
#define RB_SETTINGS_CHANGED "com.dsh.dr4wreborn.settingschanged"

static inline id RBSetting(NSString *key, id fallback) {
    id value = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key,
        (__bridge CFStringRef)RB_SETTINGS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    return value ?: fallback;
}

static inline BOOL RBSettingBool(NSString *key, BOOL fallback) {
    id value = RBSetting(key, @(fallback));
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

static inline void RBReloadSettings(void) {
    CFPreferencesSynchronize((__bridge CFStringRef)RB_SETTINGS_DOMAIN,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static inline BOOL RBWriteSetting(NSString *key, id value) {
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
        (__bridge CFStringRef)RB_SETTINGS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL saved = CFPreferencesSynchronize((__bridge CFStringRef)RB_SETTINGS_DOMAIN,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (saved) notify_post(RB_SETTINGS_CHANGED);
    return saved;
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
