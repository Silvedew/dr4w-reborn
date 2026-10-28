#pragma once
#import <UIKit/UIKit.h>

@interface UIImage (RBApplicationIcon)
+ (instancetype)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(NSInteger)format scale:(CGFloat)scale;
@end

static inline UIImage *RBApplicationIcon(NSString *bundleID) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 256; });
    UIImage *icon = [cache objectForKey:bundleID];
    if (icon) return icon;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:[UIScreen mainScreen].scale];
    if (!icon) icon = [UIImage systemImageNamed:@"app"];
    if (icon) [cache setObject:icon forKey:bundleID];
    return icon;
}
