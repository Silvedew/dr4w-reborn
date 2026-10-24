#define RB_SETTINGS_DOMAIN @"com.dsh.dr4wreborn.ci-tests"
#import "RBSettings.h"
#import "../Shared/RBSettingsStore.m"
#import <CoreFoundation/CoreFoundation.h>
#include <assert.h>

int main(void) {
    @autoreleasepool {
        // Existing Settings writes must be retained when the backend changes.
        CFPreferencesSetValue(CFSTR("enabledApps"), (__bridge CFArrayRef)@[@"test.legacy"],
            (__bridge CFStringRef)RB_SETTINGS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSetValue(CFSTR("colorIndex"), (__bridge CFNumberRef)@3,
            (__bridge CFStringRef)RB_SETTINGS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize((__bridge CFStringRef)RB_SETTINGS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        assert(RBEnabledForBundle(@"test.legacy"));
        assert([RBSetting(@"colorIndex", nil) integerValue] == 3);
        NSArray *keys = @[@"enabled", @"homeEnabled", @"volumeShortcutEnabled",
            @"showBall", @"enabledApps", @"ballOverrides"];
        for (NSString *key in keys) assert(RBWriteSetting(key, nil));
        assert(RBEnabledForBundle(@"com.apple.springboard"));
        assert(!RBEnabledForBundle(@"test.reader"));
        assert(!RBEnabledForBundle(nil));
        assert(!RBBallForBundle(@"test.reader"));
        assert(RBSettingBool(@"volumeShortcutEnabled", YES));
        assert(RBWriteSetting(@"enabledApps", @[@"test.reader"]));
        RBReloadSettings();
        assert(RBEnabledForBundle(@"test.reader"));
        assert(!RBEnabledForBundle(@"test.other"));
        assert(RBBallForBundle(@"test.reader"));
        assert(RBWriteSetting(@"showBall", @NO));
        assert(RBBallForBundle(@"test.reader")); // Legacy global setting is ignored.
        assert(RBWriteSetting(@"ballOverrides", @{@"test.reader":@NO}));
        assert(RBBallForBundle(@"test.reader")); // Legacy permanent hide is ignored.
        assert(RBWriteSetting(@"ballOverrides", @{@"test.reader":@YES}));
        assert(RBWriteSetting(@"enabled", @NO));
        assert(!RBEnabledForBundle(@"test.reader"));
        assert(!RBBallForBundle(@"test.reader"));
        assert(!RBEnabledForBundle(@"com.apple.springboard"));
        assert(RBWriteSetting(@"enabled", @YES));
        assert(RBWriteSetting(@"homeEnabled", @NO));
        assert(!RBEnabledForBundle(@"com.apple.springboard"));
        assert(RBEnabledForBundle(@"test.reader"));
        assert(RBWriteSetting(@"enabledApps", @"invalid"));
        assert(!RBEnabledForBundle(@"test.reader"));
        assert([RBSetting(@"colorIndex", nil) integerValue] == 3);
        __block BOOL observedEnabled = NO;
        __block NSUInteger callbacks = 0;
        RBObserveSettings(^{
            assert([NSThread isMainThread]);
            observedEnabled = RBEnabledForBundle(@"test.reader");
            callbacks++;
        });
        for (int i = 0; i < 100 && !callbacks; i++)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        assert(callbacks > 0 && !observedEnabled);
        [RBPreferences() testApplyRemoteValue:@[@"test.reader"] forKey:@"enabledApps"];
        for (int i = 0; i < 100 && !observedEnabled; i++)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        assert(observedEnabled); // Callback sees the refreshed cache, not the old disabled value.
        for (NSString *key in keys) assert(RBWriteSetting(key, nil));
        assert(RBWriteSetting(@"colorIndex", nil));
        NSLog(@"Settings defaults, persistence, and independent toggles passed.");
    }
    return 0;
}
