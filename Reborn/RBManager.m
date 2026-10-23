#import "RBManager.h"
#import "RBWindow.h"
#import "RBController.h"
#import "RBFloating.h"

#import <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import <dlfcn.h>

#pragma mark - volume source

@interface AVSystemController : NSObject
+ (id)sharedAVSystemController;
- (BOOL)getVolume:(float *)volume forCategory:(NSString *)category;
@end

static float          gLastVolume = -1.0f;
static NSString      *gBuffer     = @"";
static NSTimeInterval gLastPress  = 0;

BOOL RBIsSpringBoard(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"];
}

/* YES when something other than SpringBoard is frontmost (an app is on screen) */
static BOOL RBOtherAppFrontmost(void) {
    static NSString *(*frontmost)(void) = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
                         RTLD_LAZY);
        if (h) frontmost = (NSString *(*)(void))dlsym(h, "SBFrontmostApplicationDisplayIdentifier");
    });
    if (!frontmost) return NO;
    NSString *bid = frontmost();
    if (!bid) return NO;
    return ![bid isEqualToString:@"com.apple.springboard"];
}

void RBWriteLog(NSString *text) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = RBIsSpringBoard()
        ? @"/var/mobile/Media/Dr4wReborn"
        : [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
           stringByAppendingPathComponent:@"Dr4wReborn"];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:@"diag.txt"];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"[%@] %@", [df stringFromDate:[NSDate date]], text];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        return;
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
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

    _previousKey = [UIApplication sharedApplication].keyWindow;

    UIWindowScene *scene = [self activeScene];
    RBWindow *w = [[RBWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    w.windowScene = scene;
    w.windowLevel = UIWindowLevelAlert + 1000.0;
    w.backgroundColor = [UIColor clearColor];
    w.rootViewController = [[RBController alloc] init];
    w.hidden = NO;
    [w makeKeyAndVisible];
    _window = w;

    [[RBFloating shared] hide];

    /* keep it on top when an app comes to the foreground */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self->_window) return;
        [self->_window makeKeyWindow];
        [self->_window setHidden:NO];
    });
}

- (void)dismiss {
    if (!_window) return;

    _window.hidden = YES;
    _window.rootViewController = nil;
    _window = nil;

    if (_previousKey) [_previousKey makeKeyWindow];
    _previousKey = nil;

    [[RBFloating shared] show];

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
    if (now - gLastPress > 900.0) gBuffer = @"";
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
    NSLog(@"[Dr4wReborn] loaded pid %d (%@)", getpid(),
          [[NSBundle mainBundle] bundleIdentifier]);

    if (!NSClassFromString(@"UIApplication")) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

        if (RBIsSpringBoard()) {
            /* SpringBoard: volume trigger only, no ball (apps own the ball) */
            int token = 0;
            notify_register_dispatch("com.dsh.dr4wreborn.toggle", &token, dispatch_get_main_queue(), ^(int t) {
                [[RBManager shared] toggle];
            });

            CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL,
                                            RBVolumeNote,
                                            CFSTR("AVSystemController_SystemVolumeDidChangeNotification"),
                                            NULL,
                                            CFNotificationSuspensionBehaviorDeliverImmediately);

            [NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *timer) {
                RBPollVolume();
            }];
            return;
        }

        /* every app: its own ball */
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            if (![[RBManager shared] isShowing]) [[RBFloating shared] show];
        }];
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            [[RBFloating shared] hide];
        }];
        [[RBFloating shared] show];
    });
}

