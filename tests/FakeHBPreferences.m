#import <Cephei/HBPreferences.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>

@interface HBPreferences ()
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) NSMutableDictionary *cache;
@property (nonatomic, strong) NSMutableArray *callbacks;
- (void)reload;
@end

@implementation HBPreferences
+ (instancetype)preferencesForIdentifier:(NSString *)identifier {
    static NSMutableDictionary *instances;
    if (!instances) instances = [NSMutableDictionary dictionary];
    HBPreferences *preferences = instances[identifier];
    if (!preferences) {
        preferences = [self new];
        preferences.identifier = identifier;
        preferences.callbacks = [NSMutableArray array];
        [preferences reload];
        instances[identifier] = preferences;
        int token = 0;
        notify_register_dispatch([[identifier stringByAppendingString:@"/ReloadPrefs"] UTF8String],
            &token, dispatch_get_main_queue(), ^(int t) { [preferences reload]; });
    }
    return preferences;
}

- (void)reload {
    NSDictionary *values = CFBridgingRelease(CFPreferencesCopyMultiple(NULL,
        (__bridge CFStringRef)self.identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    self.cache = values ? [values mutableCopy] : [NSMutableDictionary dictionary];
    for (void (^callback)(void) in self.callbacks) callback();
}
- (id)objectForKey:(NSString *)key { return self.cache[key]; }
- (NSDictionary *)dictionaryRepresentation { return [self.cache copy]; }
- (void)setObject:(id)value forKey:(NSString *)key {
    self.cache[key] = value;
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
        (__bridge CFStringRef)self.identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)self.identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
- (void)registerPreferenceChangeBlock:(void (^)(void))callback {
    [self.callbacks addObject:[callback copy]];
    callback();
}
- (void)testApplyRemoteValue:(id)value forKey:(NSString *)key {
    // Model Cephei's guarantee: refresh the cache before invoking observers.
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
        (__bridge CFStringRef)self.identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)self.identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    [self reload];
}
@end
