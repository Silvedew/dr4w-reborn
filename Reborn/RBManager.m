#import "RBManager.h"
#import "RBWindow.h"
#import "RBController.h"
#import "RBFloating.h"
#import "RBPrefs.h"
#import <AVFoundation/AVFoundation.h>

#import <notify.h>
#import <math.h>

#pragma mark - volume source

static float          gLastVolume = -1.0f;
static NSString      *gBuffer     = @"";
static NSTimeInterval gLastPress  = 0;
static NSTimer       *gLayoutTimer = nil;
static BOOL           gDeviceLocked = YES;

static BOOL RBMayPresent(void) {
    if (RBIsSpringBoard()) return !gDeviceLocked;
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

    if (_previousKey && !_previousKey.hidden &&
        RBMayPresent())
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

#pragma mark - volume trigger

static void RBHandleVolume(float v) {
    if (!isfinite(v) || v < 0.0f || v > 1.0f) return;
    if (!RBMayPresent()) {
        gLastVolume = -1.0f;
        gBuffer = @"";
        gLastPress = 0;
        return;
    }
    if (gLastVolume < 0) { gLastVolume = v; return; }
    if (fabsf(v - gLastVolume) < 0.004f) return;

    char c = (v > gLastVolume) ? 'U' : 'D';
    gLastVolume = v;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970] * 1000.0;
    if (now - gLastPress > 900.0) gBuffer = @"";
    gLastPress = now;
    gBuffer = [gBuffer stringByAppendingFormat:@"%c", c];

    if ([gBuffer containsString:@"UD"]) {
        gBuffer = @"";
        [[RBManager shared] toggle];
    }
}

static void RBVolumeNote(CFNotificationCenterRef center, void *observer,
                         CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSDictionary *info = (__bridge NSDictionary *)userInfo;
    NSNumber *n = info[@"AVSystemController_AudioVolumeNotificationParameter"];
    if (![n isKindOfClass:[NSNumber class]]) return;
    float volume = n.floatValue;
    // Notification delivery need not originate on the UIKit thread.
    dispatch_async(dispatch_get_main_queue(), ^{ RBHandleVolume(volume); });
}

#pragma mark - startup

__attribute__((constructor))
static void RBBootstrap(void) {
    if (!NSClassFromString(@"UIApplication")) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (RBIsSpringBoard()) {
            /* SpringBoard: volume trigger only, no ball */
            int token = 0;
            notify_register_dispatch("com.dsh.dr4wreborn.toggle", &token, dispatch_get_main_queue(), ^(int t) {
                [[RBManager shared] toggle];
            });

            CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL,
                                            RBVolumeNote,
                                            CFSTR("AVSystemController_SystemVolumeDidChangeNotification"),
                                            NULL,
                                            CFNotificationSuspensionBehaviorDeliverImmediately);

            // SpringBoard can be inactive while an unlocked app is in front.
            int lockToken = 0;
            if (notify_register_dispatch("com.apple.springboard.lockstate", &lockToken,
                dispatch_get_main_queue(), ^(int t) {
                    uint64_t state = 1;
                    if (notify_get_state(t, &state) != NOTIFY_STATUS_OK) return;
                    gDeviceLocked = state != 0;
                    gLastVolume = gDeviceLocked ? -1.0f : [AVAudioSession sharedInstance].outputVolume;
                    gBuffer = @"";
                    gLastPress = 0;
                    if (gDeviceLocked) [[RBManager shared] dismiss];
                }) == NOTIFY_STATUS_OK) {
                uint64_t state = 1;
                if (notify_get_state(lockToken, &state) == NOTIFY_STATUS_OK)
                    gDeviceLocked = state != 0;
            }
            if (!gDeviceLocked) gLastVolume = [AVAudioSession sharedInstance].outputVolume;
            return;
        }

        /* every app: its own ball */
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            [[RBFloating shared] refreshVisibility];
            RBStartLayoutPolling();
        }];
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
