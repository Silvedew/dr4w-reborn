#import "RBController.h"
#import "RBManager.h"
#import "RBPrefs.h"

#import "ACEDrawingView.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - quick colour palette (4 circles)

@interface RBColorPaletteVC : UIViewController
@property (nonatomic, strong) NSArray<UIColor *> *colors;
@property (nonatomic, copy) void (^onPick)(UIColor *color);
@end

@implementation RBColorPaletteVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:
                                 [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    glass.frame = self.view.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.layer.cornerRadius = 16.0;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    [self.view addSubview:glass];

    CGFloat size = 44.0;
    CGFloat gap = 8.0;
    CGFloat width = self.colors.count * size + (self.colors.count + 1) * gap;
    self.preferredContentSize = CGSizeMake(width, size + gap * 2.0);

    CGFloat x = gap;
    for (NSUInteger i = 0; i < self.colors.count; i++) {
        UIColor *c = self.colors[i];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(x, gap, size, size);
        b.backgroundColor = c;
        b.layer.cornerRadius = size / 2.0;
        b.layer.borderWidth = 1.0;
        b.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.25].CGColor;
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(pick:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:b];
        x += size + gap;
    }
}

- (void)pick:(UIButton *)sender {
    UIColor *c = self.colors[(NSUInteger)sender.tag];
    if (self.onPick) self.onPick(c);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - controller

@interface RBLogDrawingView : ACEDrawingView
@end

@implementation RBLogDrawingView
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    CGPoint p = [t locationInView:self];
    RBWriteLog([NSString stringWithFormat:@"touch %.0f,%.0f win=%@ key=%d enabled=%d frame=%@\n",
                p.x, p.y, self.window, (int)self.window.isKeyWindow,
                (int)self.userInteractionEnabled, NSStringFromCGRect(self.frame)]);
    [super touchesBegan:touches withEvent:event];
}
@end

@interface RBController () <UIColorPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate>
@end

@implementation RBController {
    ACEDrawingView *_drawView;
    UIView         *_bar;

    UIButton       *_color;
    UIButton       *_gear;
    UIButton       *_undo;
    UIButton       *_clear;
    UIButton       *_shot;
    UIButton       *_close;

    RBColorPaletteVC *_palette;
    UIColorPickerViewController *_picker;
}

#pragma mark - life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    _drawView = [[RBLogDrawingView alloc] initWithFrame:self.view.bounds];
    _drawView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _drawView.backgroundColor = [UIColor clearColor];
    _drawView.clipsToBounds = YES;
    _drawView.drawTool = [RBPrefs tool];
    _drawView.lineColor = [RBPrefs color];
    _drawView.lineWidth = [RBPrefs lineWidth];
    _drawView.lineAlpha = 1.0;
    _drawView.draggableTextCloseImage = [UIImage systemImageNamed:@"xmark.circle.fill"];
    _drawView.draggableTextRotateImage = [UIImage systemImageNamed:@"arrow.clockwise.circle.fill"];
    [self.view addSubview:_drawView];

    [self buildBar];
}

#pragma mark - toolbar

- (UIButton *)barButton:(NSString *)symbol action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:24.0
                                                        weight:UIImageSymbolWeightMedium];
    UIImage *img = [UIImage systemImageNamed:symbol withConfiguration:cfg];
    if (!img) img = [UIImage systemImageNamed:symbol];
    [b setImage:img forState:UIControlStateNormal];
    b.tintColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)buildBar {
    CGFloat bw = 56.0;
    CGFloat bh = 6.0 * 52.0 + 16.0;
    CGRect f;
    f.origin.x = self.view.bounds.size.width - bw - 8.0;
    f.origin.y = (self.view.bounds.size.height - bh) / 2.0;
    f.size.width = bw;
    f.size.height = bh;

    _bar = [[UIVisualEffectView alloc] initWithEffect:
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    _bar.frame = f;
    _bar.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    _bar.layer.cornerRadius = 18.0;
    _bar.layer.cornerCurve = kCACornerCurveContinuous;
    _bar.layer.borderWidth = 0.5;
    _bar.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.55].CGColor;
    _bar.clipsToBounds = YES;
    _bar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                            UIViewAutoresizingFlexibleTopMargin |
                            UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:_bar];

    _color = [self barButton:@"circle.fill" action:@selector(colorTapped:)];
    _gear  = [self barButton:@"gearshape" action:@selector(settingsTapped:)];
    _undo  = [self barButton:@"arrow.uturn.backward" action:@selector(undoTapped:)];
    _clear = [self barButton:@"trash" action:@selector(clearTapped:)];
    _shot  = [self barButton:@"camera" action:@selector(shotTapped:)];
    _close = [self barButton:@"xmark.circle.fill" action:@selector(closeTapped:)];

    /* 1 设置 / 2 截图 / 3 返回(撤销) / 4 清屏 / 5 颜色 / 6 关闭 */
    NSArray<UIButton *> *buttons = @[_gear, _shot, _undo, _clear, _color, _close];
    UIView *content = ((UIVisualEffectView *)_bar).contentView;
    for (NSUInteger i = 0; i < buttons.count; i++) {
        UIButton *b = buttons[i];
        b.frame = CGRectMake(6.0, 8.0 + i * 52.0, 44.0, 44.0);
        [content addSubview:b];
    }

    [self updateColorIcon];
}

- (void)updateColorIcon {
    UIColor *c = [RBPrefs color];
    CGSize s = CGSizeMake(28.0, 28.0);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:s];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef g = ctx.CGContext;
        CGRect circle = CGRectMake(2.0, 2.0, 24.0, 24.0);
        CGContextSetFillColorWithColor(g, c.CGColor);
        CGContextFillEllipseInRect(g, circle);
        CGContextSetStrokeColorWithColor(g, [UIColor colorWithWhite:0.0 alpha:0.35].CGColor);
        CGContextSetLineWidth(g, 1.5);
        CGContextStrokeEllipseInRect(g, circle);
    }];
    [_color setImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
            forState:UIControlStateNormal];
}

#pragma mark - actions

- (void)undoTapped:(UIButton *)sender {
    [_drawView undoLatestStep];
}

- (void)clearTapped:(UIButton *)sender {
    [_drawView clear];
}

- (void)closeTapped:(UIButton *)sender {
    [[RBManager shared] dismiss];
}

- (void)shotTapped:(UIButton *)sender {
    UIImage *drawing = _drawView.image;
    CGSize size = _drawView.bounds.size;

    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *flat = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor whiteColor] setFill];
        UIRectFill(CGRectMake(0, 0, size.width, size.height));
        if (drawing) [drawing drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];

    NSData *png = UIImagePNGRepresentation(flat);
    NSString *dir = @"/var/mobile/Media/Dr4wReborn";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"shot-%.0f.png",
                       [[NSDate date] timeIntervalSince1970]]];
    BOOL ok = [png writeToFile:path atomically:YES];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:(ok ? @"已保存" : @"保存失败")
                                                               message:path
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - colour

- (void)colorTapped:(UIButton *)sender {
    /* palette open -> switch to the full wheel */
    if (_palette) {
        RBColorPaletteVC *p = _palette;
        _palette = nil;
        [p dismissViewControllerAnimated:NO completion:^{
            [self showColorWheel];
        }];
        return;
    }
    if (_picker) {
        [_picker dismissViewControllerAnimated:YES completion:nil];
        _picker = nil;
        return;
    }
    [self showPalette];
}

- (void)showPalette {
    RBColorPaletteVC *vc = [[RBColorPaletteVC alloc] init];
    vc.colors = @[[UIColor colorWithWhite:0.05 alpha:1.0],
                  [UIColor systemRedColor],
                  [UIColor systemBlueColor],
                  [UIColor systemGreenColor]];
    __weak typeof(self) weakSelf = self;
    vc.onPick = ^(UIColor *color) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf applyColor:color];
        strongSelf->_palette = nil;
    };
    vc.modalPresentationStyle = UIModalPresentationPopover;
    UIPopoverPresentationController *pop = vc.popoverPresentationController;
    pop.sourceView = _color;
    pop.sourceRect = _color.bounds;
    pop.permittedArrowDirections = UIPopoverArrowDirectionLeft | UIPopoverArrowDirectionRight;
    pop.backgroundColor = [UIColor clearColor];

    _palette = vc;
    [self presentViewController:vc animated:YES completion:^{
        vc.presentationController.delegate = self;
    }];
}

- (void)showColorWheel {
    UIColorPickerViewController *p = [[UIColorPickerViewController alloc] init];
    p.selectedColor = [RBPrefs color];
    p.supportsAlpha = NO;
    p.delegate = self;
    p.modalPresentationStyle = UIModalPresentationPopover;
    p.preferredContentSize = CGSizeMake(320.0, 420.0);
    UIPopoverPresentationController *pop = p.popoverPresentationController;
    pop.sourceView = _color;
    pop.sourceRect = _color.bounds;
    pop.permittedArrowDirections = UIPopoverArrowDirectionLeft | UIPopoverArrowDirectionRight;

    _picker = p;
    [self presentViewController:p animated:YES completion:^{
        p.presentationController.delegate = self;
    }];
}

- (void)applyColor:(UIColor *)color {
    [RBPrefs setCustomColor:color];
    _drawView.lineColor = color;
    [self updateColorIcon];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    [self applyColor:viewController.selectedColor];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    _picker = nil;
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if (presentationController.presentedViewController == _palette) _palette = nil;
    if (presentationController.presentedViewController == _picker) _picker = nil;
}

#pragma mark - settings

- (void)anchor:(UIAlertController *)sheet to:(UIView *)view {
    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = view;
        pop.sourceRect = view.bounds;
        pop.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
}

- (void)settingsTapped:(UIButton *)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"绘图设置"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"工具：%@", [RBPrefs toolName]]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [self showTools]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"线条颜色"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [self colorTapped:nil]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"线条粗细"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [self showWidths]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"一键清屏"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) { [self->_drawView clear]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    [self anchor:sheet to:sender];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showTools {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"绘图工具"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *names = [RBPrefs toolNames];
    NSArray<NSNumber *> *types = @[@(ACEDrawingToolTypePen), @(ACEDrawingToolTypeLine),
                                   @(ACEDrawingToolTypeArrow), @(ACEDrawingToolTypeRectagleStroke),
                                   @(ACEDrawingToolTypeRectagleFill), @(ACEDrawingToolTypeEllipseStroke),
                                   @(ACEDrawingToolTypeEllipseFill), @(ACEDrawingToolTypeEraser),
                                   @(ACEDrawingToolTypeDraggableText), @(ACEDrawingToolTypeTriangleStroke),
                                   @(ACEDrawingToolTypePentagonStroke), @(ACEDrawingToolTypeHexagoneStroke)];
    for (NSUInteger i = 0; i < names.count && i < types.count; i++) {
        ACEDrawingToolType t = (ACEDrawingToolType)[types[i] integerValue];
        [sheet addAction:[UIAlertAction actionWithTitle:names[i]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [RBPrefs setTool:t];
            self->_drawView.drawTool = t;
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self anchor:sheet to:_gear];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showWidths {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"线条粗细"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *widths = [RBPrefs widths];
    for (NSUInteger i = 0; i < widths.count; i++) {
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%.0f 磅", widths[i].doubleValue]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [RBPrefs setWidthIndex:(NSInteger)i];
            self->_drawView.lineWidth = widths[i].doubleValue;
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self anchor:sheet to:_gear];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
