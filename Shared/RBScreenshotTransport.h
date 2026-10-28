#pragma once
#import <Foundation/Foundation.h>
#import "RBScreenshotPolicy.h"
#include <sys/types.h>

// Only SpringBoard installs this handler. The PID comes exclusively from the kernel audit trailer.
BOOL RBStartScreenshotTransport(RBScreenshotResult (^handler)(RBScreenshotSender sender, NSTimeInterval deadline));
// Exactly one send; only a failed lookup permits trying the other rootless bootstrap alias.
// The deadline uses systemUptime; callbacks and stillCurrent run on the main queue.
void RBSendScreenshotRequest(NSTimeInterval deadline, BOOL (^stillCurrent)(void),
                             BOOL (^willSend)(void),
                             void (^completion)(RBScreenshotResult));
