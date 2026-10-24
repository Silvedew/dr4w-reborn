#import "RBSystemHooks.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <string.h>

// Signatures: theos/headers SpringBoard/SBVolumeControl.h and SBLockScreenManager.h.
@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end

@interface UIApplication (RBHomeVisibility)
- (BOOL)isShowingHomescreen;
@end

BOOL RBDeviceIsLocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    if (![cls respondsToSelector:@selector(sharedInstance)]) return YES;
    SBLockScreenManager *manager = [cls sharedInstance];
    if (![manager respondsToSelector:@selector(isUILocked)]) return YES;
    return [manager isUILocked];
}

BOOL RBHomeIsVisible(void) {
    UIApplication *app = [UIApplication sharedApplication];
    return [app respondsToSelector:@selector(isShowingHomescreen)] && [app isShowingHomescreen];
}

static void (*gOriginalUp)(id, SEL);
static void (*gOriginalDown)(id, SEL);
static void (^gOnPress)(BOOL);

static void RBIncreaseVolume(id self, SEL command) {
    gOriginalUp(self, command);
    dispatch_async(dispatch_get_main_queue(), ^{ gOnPress(YES); });
}

static void RBDecreaseVolume(id self, SEL command) {
    gOriginalDown(self, command);
    dispatch_async(dispatch_get_main_queue(), ^{ gOnPress(NO); });
}

static BOOL RBValidVolumeMethod(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char result[8] = {0};
    method_getReturnType(method, result, sizeof(result));
    return strcmp(result, @encode(void)) == 0;
}

BOOL RBInstallVolumeHooks(void (^onPress)(BOOL)) {
    Class cls = NSClassFromString(@"SBVolumeControl");
    SEL up = NSSelectorFromString(@"increaseVolume");
    SEL down = NSSelectorFromString(@"decreaseVolume");
    if (!RBValidVolumeMethod(cls, up) || !RBValidVolumeMethod(cls, down)) return NO;
    void (*hook)(Class, SEL, IMP, IMP *) = dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (!hook) {
        void *library = dlopen("/var/jb/usr/lib/libsubstrate.dylib", RTLD_NOW);
        if (!library) library = dlopen("/usr/lib/libsubstrate.dylib", RTLD_NOW);
        if (library) hook = dlsym(library, "MSHookMessageEx");
    }
    if (!hook) return NO;
    gOnPress = [onPress copy];
    hook(cls, up, (IMP)RBIncreaseVolume, (IMP *)&gOriginalUp);
    hook(cls, down, (IMP)RBDecreaseVolume, (IMP *)&gOriginalDown);
    return YES;
}
