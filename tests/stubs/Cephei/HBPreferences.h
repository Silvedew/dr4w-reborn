// Test double for the subset of the official Cephei 2.0 API used by the adapter.
#import <Foundation/Foundation.h>
@interface HBPreferences : NSObject
+ (instancetype)preferencesForIdentifier:(NSString *)identifier;
- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key;
- (NSDictionary *)dictionaryRepresentation;
- (void)registerPreferenceChangeBlock:(void (^)(void))callback;
- (void)testApplyRemoteValue:(id)value forKey:(NSString *)key;
@end
