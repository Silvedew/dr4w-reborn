#pragma once
#import <Foundation/Foundation.h>

#ifndef RB_BUILD_VERSION
#define RB_BUILD_VERSION "local"
#endif

static inline void RBDiagnostic(NSString *event, NSString *details) {
    NSLog(@"[Dr4wReborn %@] event=%@ bundle=%@ pid=%d %@", @RB_BUILD_VERSION, event,
        [NSBundle mainBundle].bundleIdentifier ?: @"unknown", [NSProcessInfo processInfo].processIdentifier,
        details ?: @"");
}
