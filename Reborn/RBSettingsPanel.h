#pragma once
#import <UIKit/UIKit.h>
#import "ACEDrawingView.h"

@interface RBSettingsPanel : UIViewController
@property (nonatomic, copy) void (^closeHandler)(void);
@property (nonatomic, copy) void (^hideBallHandler)(void);
@property (nonatomic, copy) void (^toolChange)(ACEDrawingToolType);
@property (nonatomic, copy) void (^toolbarScaleChange)(CGFloat);
@property (nonatomic, copy) void (^toolbarScaleCommit)(CGFloat);
@property (nonatomic) CGFloat toolbarScale;
- (void)commitPendingChanges;
// Publishes preferredContentSize only when it changes; parents use the standard child-size callback.
- (void)updateAvailableSize:(CGSize)size;
- (void)refreshApplicationStates;
@end
