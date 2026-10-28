#pragma once
#import <Foundation/Foundation.h>
#import "RBScreenshotPolicy.h"

void RBStartScreenshotService(void);
// The manager applies its existing home-screen presentation policy before calling locally.
RBScreenshotResult RBTakeLocalSystemScreenshot(NSTimeInterval deadline);
