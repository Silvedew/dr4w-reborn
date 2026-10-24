#import "RBManager.h"
#import "RBWindow.h"
#import "RBController.h"
#import "RBFloating.h"
#import "RBPrefs.h"
#import "RBSystemHooks.h"
#import "RBSettings.h"
#import <QuartzCore/QuartzCore.h>

#import <notify.h>
static NSTimer       *gLayoutTimer = nil;
static RBVolumeSequence gVolumeSequence = {0};

static BOOL RBMayPresent(void) {
    if (!RBEnabledForBundle([[NSBundle mainBundle] bundleIdentifier])) return NO;
    if (RBIsSpringBoard()) return !RBDeviceIsLocked() && RBHomeIsVisible();
    return [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
}

static void RBStopLayoutPolling(void) {
    [gLayoutTimer invalidate];
    gLayoutTimer = nil;
}

static void RBStartLayoutPolling(void) {
    if (RBIsSpringBoard()) return;
    if ([RBPrefs isAppDisabled:[[NSBundle mainBundle] bundleIdentifier]] &&
        ![[RBManager shared] isShowing]) return;
    if (gLayoutTimer) return;
    __block CGRect lastBounds = CGRectNull;
    gLayoutTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        CGRect host = RBHostBounds();
        if (CGRectEqualToRect(host, lastBounds)) return;
        lastBounds = host;
        [[RBManager shared] layoutForCurrentHost];
    }];
    gLayoutTimer.tolerance = 0.2;
}

BOOL RBIsSpringBoard(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"];
}

/* Split View / Slide Over: the scene only owns part of the screen, so every
   overlay must live inside this rect instead of the full screen. */
CGRect RBHostBounds(void) {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive)
            return ((UIWindowScene *)s).coordinateSpace.bounds;
    }
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]])
            return ((UIWindowScene *)s).coordinateSpace.bounds;
    }
    return [UIScreen mainScreen].bounds;
}

@interface RBManager ()
- (void)toggle;
@end

@implementation RBManager {
    RBWindow *_window;
    UIWindow *_previousKey;
}

+ (instancetype)shared {
    static RBManager *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[RBManager alloc] init]; });
    return shared;
}

#pragma mark - window

- (UIWindowScene *)activeScene {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
    }
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

- (BOOL)isShowing {
    return _window != nil && !_window.hidden;
}

- (void)present {
    if ([self isShowing]) return;
    if (!RBMayPresent()) return;

    _previousKey = [UIApplication sharedApplication].keyWindow;

    RBWindow *w = [[RBWindow alloc] initWithFrame:RBHostBounds()];
    w.windowScene = [self activeScene];
    w.windowLevel = UIWindowLevelAlert + 1000.0;
    w.backgroundColor = [UIColor clearColor];
    w.rootViewController = [[RBController alloc] init];
    w.hidden = NO;
    [w makeKeyAndVisible];
    _window = w;
    RBStartLayoutPolling();

    [[RBFloating shared] hide];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self->_window != w) return;
        if (!RBMayPresent()) return;
        [self->_window makeKeyWindow];
        [self->_window setHidden:NO];
    });
}

- (void)dismiss {
    if (!_window) return;

    _window.hidden = YES;
    _window.rootViewController = nil;
    _window = nil;

    BOOL canRestoreKey = RBIsSpringBoard() ? !RBDeviceIsLocked() :
        [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
    if (_previousKey && !_previousKey.hidden && canRestoreKey)
        [_previousKey makeKeyWindow];
    _previousKey = nil;

    [[RBFloating shared] refreshVisibility];
    if ([RBPrefs isAppDisabled:[[NSBundle mainBundle] bundleIdentifier]]) RBStopLayoutPolling();
}

- (void)toggle {
    if ([self isShowing]) [self dismiss];
    else [self present];
}

- (void)layoutForCurrentHost {
    if (_window) _window.frame = RBHostBounds();
    [[RBFloating shared] applyPrefs];
}

@end

#pragma mark - startup

__attribute__((constructor))
static void RBBootstrap(void) {
    if (!NSClassFromString(@"UIApplication")) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        RBReloadSettings();
        __block BOOL wasEnabled = RBEnabledForBundle([[NSBundle mainBundle] bundleIdentifier]);
        int settingsToken = 0;
        notify_register_dispatch(RB_SETTINGS_CHANGED, &settingsToken, dispatch_get_main_queue(), ^(int t) {
            RBReloadSettings();
            gVolumeSequence = (RBVolumeSequence){0};
            if (!RBMayPresent()) [[RBManager shared] dismiss];
            BOOL enabled = RBEnabledForBundle([[NSBundle mainBundle] bundleIdentifier]);
            if (enabled && !wasEnabled)
                [[RBFloating shared] restoreForForeground];
            else [[RBFloating shared] refreshVisibility];
            wasEnabled = enabled;
            RBStopLayoutPolling();
            if (RBMayPresent()) RBStartLayoutPolling();
        });

        int toggleToken = 0;
        notify_register_dispatch("com.dsh.dr4wreborn.toggle", &toggleToken, dispatch_get_main_queue(), ^(int t) {
            if (RBMayPresent()) [[RBManager shared] toggle];
        });

        if (RBIsSpringBoard()) {
            BOOL installed = RBInstallVolumeHooks(^(BOOL up) {
                BOOL allowed = RBSettingBool(@"enabled", YES) &&
                    RBSettingBool(@"volumeShortcutEnabled", YES) && !RBDeviceIsLocked();
                if (RBVolumePress(&gVolumeSequence, up, CACurrentMediaTime(), allowed))
                    notify_post("com.dsh.dr4wreborn.toggle");
            });
            NSLog(@"[Dr4wReborn] volume button hooks: %@", installed ? @"ready" : @"unavailable");
            int lockToken = 0;
            notify_register_dispatch("com.apple.springboard.lockstate", &lockToken,
                dispatch_get_main_queue(), ^(int t) {
                    gVolumeSequence = (RBVolumeSequence){0};
                    if (RBDeviceIsLocked()) [[RBManager shared] dismiss];
                });
            return;
        }

        /* every app: its own ball */
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            RBReloadSettings();
            [[RBFloating shared] restoreForForeground];
            RBStartLayoutPolling();
        }];
        [nc addObserverForName:UISceneDidActivateNotification object:nil
                         queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            RBReloadSettings();
            [[RBFloating shared] restoreForForeground];
            RBStartLayoutPolling();
        }];
        for (NSNotificationName name in @[UISceneWillDeactivateNotification, UISceneDidDisconnectNotification]) {
            [nc addObserverForName:name object:nil queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                [[RBFloating shared] sceneDidDeactivate:note.object];
            }];
        }
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            [[RBFloating shared] hide];
            RBStopLayoutPolling();
        }];
        [nc addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            [[RBManager shared] dismiss];
            [[RBFloating shared] hide];
            RBStopLayoutPolling();
        }];
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            [[RBFloating shared] refreshVisibility];
            RBStartLayoutPolling();
        }
    });
}
