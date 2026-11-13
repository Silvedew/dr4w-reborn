#pragma once
#import <Foundation/Foundation.h>

// nil means the input already excludes Pencil (or is invalid).
static inline NSArray<NSNumber *> *RBPencilFilteredTouchTypes(NSArray *types, NSNumber *pencil) {
    if (![types isKindOfClass:NSArray.class] || ![types containsObject:pencil]) return nil;
    NSMutableArray *filtered = [types mutableCopy];
    [filtered removeObject:pencil];
    return filtered;
}

static inline BOOL RBPencilShouldRestoreTouchTypes(NSArray *current, NSArray *original, NSNumber *pencil) {
    NSArray *filtered = RBPencilFilteredTouchTypes(original, pencil);
    return filtered && [current isEqualToArray:filtered];
}
