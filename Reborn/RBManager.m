#import "RBManager.h"
#import "RBWindow.h"
#import "RBController.h"
#import "RBBrushPopover.h"
#import "RBSettingsPanel.h"
#import "RBFloating.h"
#import "RBPrefs.h"
#import "RBSystemHooks.h"
#import "RBSettings.h"
#import "RBDiagnostics.h"
#import <QuartzCore/QuartzCore.h>

#import <notify.h>
static NSTimer       *gLayoutTimer = nil;
static RBVolumeSequence gVolumeSequence = {0};

@interface RBManager ()
- (CGRect)currentHostBounds;
- (void)sceneDidDeactivate:(UIScene *)scene;
@end

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
        CGRect host = [[RBManager shared] currentHostBounds];
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
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (!window.hidden && window.windowLevel == UIWindowLevelNormal && window.rootViewController)
            return window.bounds;
    }
    return [UIScreen mainScreen].bounds;
}

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
        if (RBIsSpringBoard() && [s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

- (BOOL)isShowing {
    return _window != nil && !_window.hidden;
}

- (void)present {
    [self presentFromFloatingWindow:nil center:CGPointZero];
}

- (void)presentFromFloatingWindow:(UIWindow *)sourceWindow center:(CGPoint)center {
    if ([self isShowing]) return;
    if (!RBMayPresent()) {
        RBDiagnostic(@"present.skipped", @"policy-or-foreground");
        return;
    }
    UIWindowScene *scene = sourceWindow ? sourceWindow.windowScene : [self activeScene];
    if (sourceWindow && scene && (scene.activationState != UISceneActivationStateForegroundActive ||
        ![UIApplication.sharedApplication.connectedScenes containsObject:scene])) return;
    if (!RBPolicyCanHostWindow(scene != nil, [UIApplication sharedApplication].connectedScenes.count)) {
        RBDiagnostic(@"present.skipped", @"no-active-scene");
        return;
    }

    _previousKey = nil;
    if (scene) {
        for (UIWindow *window in scene.windows) {
            if (window.isKeyWindow) {
                _previousKey = window;
                break;
            }
        }
    } else _previousKey = [UIApplication sharedApplication].keyWindow;

    RBWindow *w = [[RBWindow alloc] initWithFrame:scene ? scene.coordinateSpace.bounds : RBHostBounds()];
    if (scene) w.windowScene = scene;
    else if (sourceWindow) w.screen = sourceWindow.screen;
    w.windowLevel = UIWindowLevelAlert + 1000.0;
    w.backgroundColor = [UIColor clearColor];
    w.opaque = NO;
    RBController *controller = [[RBController alloc] init];
    if (sourceWindow) [controller setInitialToolbarAnchor:center fromWindow:sourceWindow];
    w.rootViewController = controller;
    [w layoutIfNeeded];
    w.hidden = NO;
    [w makeKeyAndVisible];
    _window = w;
    RBDiagnostic(@"present.shown", scene ? @"scene=active" : @"scene=legacy");
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

- (void)dismissFromUser {
    [(RBController *)_window.rootViewController syncFloatingPositionAfterUserClose];
    [self dismiss];
}

- (void)dismiss {
    if (!_window) return;

    for (UIViewController *child in _window.rootViewController.childViewControllers) {
        if ([child isKindOfClass:RBBrushPopover.class]) [(RBBrushPopover *)child commitPendingChanges];
        if ([child isKindOfClass:RBSettingsPanel.class]) [(RBSettingsPanel *)child commitPendingChanges];
    }
    _window.hidden = YES;
    _window.rootViewController = nil;
    _window = nil;

    BOOL canRestoreKey = RBIsSpringBoard() ? !RBDeviceIsLocked() :
        [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
    if (_previousKey && !_previousKey.hidden && canRestoreKey &&
        (!_previousKey.windowScene || _previousKey.windowScene.activationState == UISceneActivationStateForegroundActive))
        [_previousKey makeKeyWindow];
    _previousKey = nil;

    [[RBFloating shared] refreshVisibility];
    if ([RBPrefs isAppDisabled:[[NSBundle mainBundle] bundleIdentifier]]) RBStopLayoutPolling();
}

- (void)toggle {
    if ([self isShowing]) [self dismissFromUser];
    else [self present];
}

- (CGRect)currentHostBounds {
    return _window.windowScene ? _window.windowScene.coordinateSpace.bounds : RBHostBounds();
}

- (void)sceneDidDeactivate:(UIScene *)scene {
    if (_window.windowScene == scene) [self dismiss];
}

- (void)layoutForCurrentHost {
    if (_window) _window.frame = [self currentHostBounds];
    [[RBFloating shared] applyPrefs];
}

- (void)applySettings {
    [(RBController *)_window.rootViewController refreshToolbarPreferences];
}

@end

#pragma mark - startup

__attribute__((constructor))
static void RBBootstrap(void) {
    RBDiagnostic(@"loaded", @"awaiting-main-thread");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSBundle *bundle = [NSBundle mainBundle];
        if (![bundle.bundleURL.pathExtension.lowercaseString isEqualToString:@"app"] ||
            !bundle.bundleIdentifier.length || bundle.infoDictionary[@"NSExtension"] ||
            !NSClassFromString(@"UIApplication")) {
            RBDiagnostic(@"initialize.skipped", @"not-a-UIKit-app");
            return;
        }
        static dispatch_once_t once;
        dispatch_once(&once, ^{
        if (RBIsSpringBoard()) RBStartSettingsService();
        RBReloadSettings();
        __block BOOL wasEnabled = RBEnabledForBundle([[NSBundle mainBundle] bundleIdentifier]);
        RBDiagnostic(@"initialized", [NSString stringWithFormat:@"enabled=%d state=%ld scenes=%lu",
            wasEnabled,
            (long)[UIApplication sharedApplication].applicationState,
            (unsigned long)[UIApplication sharedApplication].connectedScenes.count]);
        RBObserveSettings(^{
            gVolumeSequence = (RBVolumeSequence){0};
            [[RBManager shared] applySettings];
            if (!RBMayPresent()) [[RBManager shared] dismiss];
            BOOL enabled = RBEnabledForBundle([[NSBundle mainBundle] bundleIdentifier]);
            if (enabled && !wasEnabled)
                [[RBFloating shared] restoreForForeground];
            else [[RBFloating shared] refreshVisibility];
            wasEnabled = enabled;
            RBDiagnostic(@"settings.updated", [NSString stringWithFormat:@"enabled=%d", enabled]);
            RBStopLayoutPolling();
            if (RBMayPresent()) RBStartLayoutPolling();
        });

        int toggleToken = 0;
        notify_register_dispatch("com.dsh.dr4wreborn.toggle", &toggleToken, dispatch_get_main_queue(), ^(int t) {
            BOOL allowed = RBMayPresent();
            RBDiagnostic(@"toggle.received", [NSString stringWithFormat:@"enabled=%d allowed=%d state=%ld scenes=%lu",
                RBEnabledForBundle([[NSBundle mainBundle] bundleIdentifier]), allowed,
                (long)[UIApplication sharedApplication].applicationState,
                (unsigned long)[UIApplication sharedApplication].connectedScenes.count]);
            if (allowed) [[RBManager shared] toggle];
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
                [[RBManager shared] sceneDidDeactivate:note.object];
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
    });
}
