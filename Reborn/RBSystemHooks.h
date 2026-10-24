#import <Foundation/Foundation.h>

BOOL RBDeviceIsLocked(void);
BOOL RBHomeIsVisible(void);
BOOL RBInstallVolumeHooks(void (^onPress)(BOOL up));
