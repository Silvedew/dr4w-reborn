#import "RBScreenshotService.h"
#import "RBScreenshotTransport.h"
#import "RBSettings.h"
#import "RBManager.h"
#import "RBSystemHooks.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <string.h>
#include <dlfcn.h>

static bool RBIdentityMatches(void *context, RBScreenshotSender sender) {
    (void)context;
    int (*query)(int, int, uint64_t, void *, int) = dlsym(RTLD_DEFAULT, "proc_pidinfo");
    return RBScreenshotIdentityMatches(sender, query);
}

static BOOL gCapturePending;
static uint64_t gCaptureGeneration;

static BOOL RBMethodHasType(id object, SEL selector, const char *result, const char *argument) {
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != (argument ? 3u : 2u)) return NO;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, result)) return NO;
    if (argument) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (strcmp(type, argument)) return NO;
    }
    return YES;
}

static bool RBForegroundSender(void *context, int pid) {
    (void)context;
    id application = UIApplication.sharedApplication;
    SEL selector = NSSelectorFromString(@"_hasForegroundAppWithPID:");
    if (!RBMethodHasType(application, selector, @encode(BOOL), @encode(int))) return false;
    return ((BOOL (*)(id, SEL, int))objc_msgSend)(application, selector, pid);
}

static bool RBEnabledSender(void *context, int pid) {
    (void)context;
    Class cls = NSClassFromString(@"SBApplicationController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (!RBMethodHasType(cls, shared, @encode(id), NULL)) return false;
    id controller = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
    SEL lookup = NSSelectorFromString(@"applicationWithPid:");
    id application = nil;
    if (RBMethodHasType(controller, lookup, @encode(id), @encode(int)))
        application = ((id (*)(id, SEL, int))objc_msgSend)(controller, lookup, pid);
    else if (RBMethodHasType(controller, lookup, @encode(id), @encode(NSInteger)))
        application = ((id (*)(id, SEL, NSInteger))objc_msgSend)(controller, lookup, (NSInteger)pid);
    else return false;
    Class applicationClass = NSClassFromString(@"SBApplication");
    SEL bundleSelector = NSSelectorFromString(@"bundleIdentifier");
    if (!applicationClass || ![application isKindOfClass:applicationClass] ||
        !RBMethodHasType(application, bundleSelector, @encode(id), NULL)) return false;
    id bundle = ((id (*)(id, SEL))objc_msgSend)(application, bundleSelector);
    return [bundle isKindOfClass:NSString.class] && RBEnabledForBundle(bundle);
}

static bool RBCaptureSupported(void *context) {
    (void)context;
    return RBMethodHasType(UIApplication.sharedApplication, NSSelectorFromString(@"takeScreenshot"), @encode(void), NULL);
}

static RBScreenshotResult RBInvokeSystemScreenshot(NSTimeInterval deadline) {
    if (!NSThread.isMainThread || !RBIsSpringBoard() || RBDeviceIsLocked() ||
        gCapturePending || !RBCaptureSupported(NULL))
        return RBScreenshotRejected;
    gCapturePending = YES;
    uint64_t generation = ++gCaptureGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation == gCaptureGeneration) gCapturePending = NO;
    });
    @try {
        if (NSProcessInfo.processInfo.systemUptime >= deadline) {
            gCapturePending = NO;
            return RBScreenshotRejected;
        }
        ((void (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, NSSelectorFromString(@"takeScreenshot"));
        return RBScreenshotAccepted;
    } @catch (__unused NSException *exception) {
        return RBScreenshotUncertain;
    }
}

RBScreenshotResult RBTakeLocalSystemScreenshot(NSTimeInterval deadline) {
    if (!RBHomeIsVisible() || !RBEnabledForBundle(@"com.apple.springboard")) return RBScreenshotRejected;
    return RBInvokeSystemScreenshot(deadline);
}

void RBStartScreenshotService(void) {
    if (!NSThread.isMainThread || !RBIsSpringBoard()) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationUserDidTakeScreenshotNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                gCapturePending = NO;
                gCaptureGeneration++;
            }];
    });
    RBStartScreenshotTransport(^RBScreenshotResult(RBScreenshotSender sender, NSTimeInterval deadline) {
        if (RBDeviceIsLocked()) return RBScreenshotRejected;
        RBScreenshotAuthorization provider = {NULL, RBIdentityMatches, RBForegroundSender, RBEnabledSender, RBCaptureSupported};
        @try {
            if (!RBScreenshotAuthorize(sender, &provider) || RBDeviceIsLocked() ||
                !RBScreenshotAuthorize(sender, &provider)) return RBScreenshotRejected;
            return RBInvokeSystemScreenshot(deadline);
        } @catch (__unused NSException *exception) {
            return RBScreenshotRejected;
        }
    });
}
