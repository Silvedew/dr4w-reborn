#define RB_SETTINGS_DOMAIN @"com.dsh.dr4wreborn.ci-tests"
#import "RBSettings.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
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
        assert(!RBBallForBundle(@"test.reader")); // Enabled != visible ball.
        assert(RBWriteSetting(@"showBall", @YES));
        assert(RBBallForBundle(@"test.reader"));
        assert(RBWriteSetting(@"ballOverrides", @{@"test.reader":@NO}));
        assert(!RBBallForBundle(@"test.reader"));
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
        for (NSString *key in keys) assert(RBWriteSetting(key, nil));
        NSLog(@"Settings defaults, persistence, and independent toggles passed.");
    }
    return 0;
}
