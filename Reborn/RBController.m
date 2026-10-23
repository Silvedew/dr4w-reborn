#import "RBController.h"
#import "RBManager.h"
#import "RBPrefs.h"

#import "ACEDrawingView.h"
#import <QuartzCore/QuartzCore.h>

@implementation RBController {
    ACEDrawingView *_drawView;
    UIView         *_bar;
    UIButton       *_gear;
    UIButton       *_undo;
    UIButton       *_clear;
    UIButton       *_shot;
    UIButton       *_close;
}

#pragma mark - life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    _drawView = [[ACEDrawingView alloc] initWithFrame:self.view.bounds];
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
    CGFloat bh = 5.0 * 52.0 + 16.0;
    CGRect f;
    f.origin.x = self.view.bounds.size.width - bw - 8.0;
    f.origin.y = (self.view.bounds.size.height - bh) / 2.0;
    f.size.width = bw;
    f.size.height = bh;

    _bar = [[UIView alloc] initWithFrame:f];
    _bar.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.86];
    _bar.layer.cornerRadius = 18.0;
    _bar.clipsToBounds = YES;
    _bar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                            UIViewAutoresizingFlexibleTopMargin |
                            UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:_bar];

    _gear  = [self barButton:@"gearshape" action:@selector(settingsTapped:)];
    _undo  = [self barButton:@"arrow.uturn.backward" action:@selector(undoTapped:)];
    _clear = [self barButton:@"trash" action:@selector(clearTapped:)];
    _shot  = [self barButton:@"camera" action:@selector(shotTapped:)];
    _close = [self barButton:@"xmark.circle.fill" action:@selector(closeTapped:)];

    NSArray<UIButton *> *buttons = @[_gear, _undo, _clear, _shot, _close];
    for (NSUInteger i = 0; i < buttons.count; i++) {
        UIButton *b = buttons[i];
        b.frame = CGRectMake(6.0, 8.0 + i * 52.0, 44.0, 44.0);
        [_bar addSubview:b];
    }
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
                                            handler:^(UIAlertAction *a) { [self showColors]; }]];
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

- (void)showColors {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"线条颜色"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *names = [RBPrefs colorNames];
    NSArray<UIColor *> *colors = [RBPrefs colors];
    for (NSUInteger i = 0; i < names.count && i < colors.count; i++) {
        [sheet addAction:[UIAlertAction actionWithTitle:names[i]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [RBPrefs setColorIndex:(NSInteger)i];
            self->_drawView.lineColor = colors[i];
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
