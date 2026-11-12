#import <UIKit/UIKit.h>

@interface RBWindow : UIWindow
@property (nonatomic, weak) UIView *drawingView;
- (void)updatePencilRouting;
- (void)stopPencilRouting;
@end
