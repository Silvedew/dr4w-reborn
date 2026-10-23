#import "RBManager.h"
#import "RBWindow.h"
#import "RBController.h"

#import <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

#pragma mark - volume source

@interface AVSystemController : NSObject
+ (id)sharedAVSystemController;
- (BOOL)getVolume:(float *)volume forCategory:(NSString *)category;
@end

static float          gLastVolume = -1.0f;
static NSString      *gBuffer     = @"";
static NSTimeInterval gLastPress  = 0;

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

    _previousKey = [UIApplication sharedApplication].keyWindow;

    RBWindow *w = [[RBWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    w.windowScene = [self activeScene];
    w.windowLevel = UIWindowLevelAlert + 10.0;
    w.backgroundColor = [UIColor clearColor];
    w.rootViewController = [[RBController alloc] init];
    w.hidden = NO;
    [w makeKeyAndVisible];
    _window = w;

    NSLog(@"[Dr4wReborn] presented");
}

- (void)dismiss {
    if (!_window) return;

    _window.hidden = YES;
    _window.rootViewController = nil;
    _window = nil;

    if (_previousKey) [_previousKey makeKeyWindow];
    _previousKey = nil;

    NSLog(@"[Dr4wReborn] dismissed");
}

- (void)toggle {
    if ([self isShowing]) [self dismiss];
    else [self present];
}

@end

#pragma mark - volume trigger

static void RBHandleVolume(float v) {
    if (gLastVolume < 0) { gLastVolume = v; return; }
    if (fabsf(v - gLastVolume) < 0.004f) return;

    char c = (v > gLastVolume) ? 'U' : 'D';
    gLastVolume = v;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970] * 1000.0;
    if (now - gLastPress > 650.0) gBuffer = @"";
    gLastPress = now;
    gBuffer = [gBuffer stringByAppendingFormat:@"%c", c];

    if ([gBuffer containsString:@"UD"]) {
        gBuffer = @"";
        [[RBManager shared] toggle];
    }
}

static void RBPollVolume(void) {
    Class avc = NSClassFromString(@"AVSystemController");
    if (!avc) return;
    id av = ((id (*)(id, SEL))objc_msgSend)((id)avc, sel_registerName("sharedAVSystemController"));
    if (!av) return;

    float v = -1.0f;
    BOOL ok = ((BOOL (*)(id, SEL, float *, NSString *))objc_msgSend)(
                av, sel_registerName("getVolume:forCategory:"), &v, @"Audio/Video");
    if (!ok || v < 0.0f) return;
    RBHandleVolume(v);
}

static void RBVolumeNote(CFNotificationCenterRef center, void *observer,
                         CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSDictionary *info = (__bridge NSDictionary *)userInfo;
    NSNumber *n = info[@"AVSystemController_AudioVolumeNotificationParameter"];
    if (n) RBHandleVolume(n.floatValue);
}

__attribute__((constructor))
static void RBBootstrap(void) {
    NSLog(@"[Dr4wReborn] loaded pid %d", getpid());

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        int token = 0;
        notify_register_dispatch("com.dsh.dr4wreborn.toggle", &token, dispatch_get_main_queue(), ^(int t) {
            [[RBManager shared] toggle];
        });

        CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL,
                                        RBVolumeNote,
                                        CFSTR("AVSystemController_SystemVolumeDidChangeNotification"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            RBPollVolume();
        }];
    });
}

