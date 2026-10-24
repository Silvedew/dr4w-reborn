#import <UIKit/UIKit.h>
#import "ACEDrawingView.h"

@interface RBPrefs : NSObject

+ (ACEDrawingToolType)tool;
+ (void)setTool:(ACEDrawingToolType)tool;
+ (NSString *)toolName;

+ (NSInteger)colorIndex;
+ (UIColor *)color;
+ (void)setColorIndex:(NSInteger)index;

+ (BOOL)hasCustomColor;
+ (UIColor *)customColor;
+ (void)setCustomColor:(UIColor *)color;

+ (NSInteger)widthIndex;
+ (CGFloat)lineWidth;
+ (void)setWidthIndex:(NSInteger)index;

+ (NSArray<NSString *> *)toolNames;
+ (NSArray<NSString *> *)colorNames;
+ (NSArray<UIColor *> *)colors;
+ (NSArray<NSNumber *> *)widths;

+ (CGPoint)floatCenter;
+ (void)setFloatCenter:(CGPoint)center;

/* floating ball */
+ (CGFloat)ballSize;                 /* 44 / 56 / 64 */
+ (void)setBallSize:(CGFloat)size;
+ (CGFloat)ballAlpha;                /* 0.6 / 0.8 / 1.0 */
+ (void)setBallAlpha:(CGFloat)alpha;

/* per-app switch */
+ (BOOL)isAppDisabled:(NSString *)bundleID;

@end
