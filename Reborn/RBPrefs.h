#import <UIKit/UIKit.h>
#import "ACEDrawingView.h"

@interface RBPrefs : NSObject

+ (ACEDrawingToolType)tool;
+ (void)setTool:(ACEDrawingToolType)tool;
+ (NSString *)toolName;

+ (NSInteger)colorIndex;
+ (UIColor *)color;
+ (void)setColorIndex:(NSInteger)index;

+ (NSInteger)widthIndex;
+ (CGFloat)lineWidth;
+ (void)setWidthIndex:(NSInteger)index;

+ (NSArray<NSString *> *)toolNames;
+ (NSArray<UIColor *> *)colors;
+ (NSArray<NSNumber *> *)widths;

@end
