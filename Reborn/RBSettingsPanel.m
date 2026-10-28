#import "RBSettingsPanel.h"
#import "RBChrome.h"
#import "RBPrefs.h"
#import "RBSettings.h"
#import "RBSettingsPanelLayout.h"
#import "RBAppCatalog.h"
#import "RBApplicationIcon.h"
#import "RBFloating.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

typedef NS_ENUM(NSInteger, RBSettingsPage) {
    RBSettingsMain, RBSettingsTools, RBSettingsBallSize, RBSettingsBallAlpha,
    RBSettingsToolbarSize, RBSettingsApplications, RBSettingsDisableConfirmation
};

@interface RBSettingsSwitch : UISwitch
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *applicationName;
@end
@implementation RBSettingsSwitch
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(self.bounds, -4, -6.5), point);
}
@end

@interface RBSettingsPanel () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@end

@implementation RBSettingsPanel {
    UIView *_content;
    UILabel *_title;
    RBChromeButton *_back;
    RBChromeButton *_close;
    UITextField *_search;
    UITableView *_table;
    UISlider *_scaleSlider;
    UILabel *_scaleLabel;
    RBSettingsPage _page;
    BOOL _scaleDirty;
    BOOL _loading;
    BOOL _saving;
    NSArray<NSDictionary *> *_applications;
    NSArray<NSDictionary *> *_filteredApplications;
    NSString *_errorMessage;
    NSString *_pendingBundle;
    NSString *_pendingName;
    BOOL _pendingEnabled;
    int _settingsToken;
}
@synthesize toolbarScale = _toolbarScale;

- (void)setToolbarScale:(CGFloat)toolbarScale {
    _toolbarScale = toolbarScale;
    if (!_scaleSlider.tracking) {
        _scaleSlider.value = toolbarScale;
        [self updateScaleLabel];
    }
}

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _toolbarScale = [RBPrefs toolbarScale];
        _settingsToken = -1;
        self.preferredContentSize = CGSizeMake(RBSettingsPanelWidth, RBSettingsPanelHeight);
    }
    return self;
}
- (void)dealloc {
    if (_settingsToken >= 0) notify_cancel(_settingsToken);
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)loadView {
    self.view = [[RBChromeSurface alloc] initWithFrame:CGRectZero];
    self.view.opaque = NO;
    self.view.accessibilityViewIsModal = YES;
}
- (RBChromeButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    RBChromeButton *button = [[RBChromeButton alloc] initWithFrame:CGRectZero];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.titleLabel.numberOfLines = 0;
    button.accessibilityLabel = button.largeContentTitle = title;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    _content = [UIView new];
    _content.clipsToBounds = YES;
    _content.layer.cornerRadius = self.view.layer.cornerRadius;
    _content.layer.cornerCurve = self.view.layer.cornerCurve;
    [self.view addSubview:_content];
    _back = [self buttonWithTitle:@"" action:@selector(goBack:)];
    [_back setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    _back.accessibilityLabel = _back.largeContentTitle = @"返回设置";
    [_content addSubview:_back];
    _close = [self buttonWithTitle:@"" action:@selector(close:)];
    [_close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    _close.accessibilityLabel = _close.largeContentTitle = @"关闭设置";
    [_content addSubview:_close];
    _title = [UILabel new];
    _title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _title.adjustsFontForContentSizeCategory = YES;
    _title.adjustsFontSizeToFitWidth = YES;
    _title.minimumScaleFactor = 0.7;
    _title.textColor = UIColor.labelColor;
    _title.textAlignment = NSTextAlignmentCenter;
    _title.accessibilityTraits = UIAccessibilityTraitHeader;
    [_content addSubview:_title];
    _search = [UITextField new];
    _search.placeholder = @"搜索名称或 Bundle ID";
    _search.accessibilityLabel = @"搜索 App 名称或 Bundle ID";
    _search.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _search.adjustsFontForContentSizeCategory = YES;
    _search.textColor = UIColor.labelColor;
    _search.tintColor = UIColor.labelColor;
    _search.backgroundColor = UIColor.tertiarySystemFillColor;
    _search.layer.cornerRadius = 12;
    _search.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 44)];
    _search.leftViewMode = UITextFieldViewModeAlways;
    _search.clearButtonMode = UITextFieldViewModeWhileEditing;
    _search.autocorrectionType = UITextAutocorrectionTypeNo;
    _search.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _search.returnKeyType = UIReturnKeyDone;
    _search.delegate = self;
    [_search addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];
    [_content addSubview:_search];
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = UIColor.clearColor;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [_content addSubview:_table];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(contentSizeChanged:)
        name:UIContentSizeCategoryDidChangeNotification object:nil];
    __weak typeof(self) weakSelf = self;
    notify_register_dispatch(RB_SETTINGS_CHANGED, &_settingsToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf refreshApplicationStates];
    });
    [self showPage:RBSettingsMain];
}
- (void)updateAvailableSize:(CGSize)size {
    RBSettingsPanelSize panel = RBSettingsPanelSizeForHost(size.width, size.height);
    CGSize preferred = CGSizeMake(panel.width, panel.height);
    if (!CGSizeEqualToSize(preferred, self.preferredContentSize)) self.preferredContentSize = preferred;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    _content.frame = self.view.bounds;
    _back.frame = CGRectMake(4, 4, 44, 44);
    _close.frame = CGRectMake(MAX(4, width - 48), 4, 44, 44);
    _title.frame = CGRectMake(52, 4, MAX(0, width - 104), 44);
    _search.frame = CGRectMake(12, RBSettingsPanelHeader, MAX(0, width - 24), 44);
    BOOL hasSearch = _page == RBSettingsApplications;
    CGFloat top = RBSettingsPanelHeader + (hasSearch ? RBSettingsPanelSearch : 0);
    _table.frame = CGRectMake(0, top, width, RBSettingsPanelScrollHeight(self.view.bounds.size.height, hasSearch));
}
- (void)showPage:(RBSettingsPage)page {
    [self commitPendingChanges];
    if (page != RBSettingsApplications) [_search resignFirstResponder];
    _page = page;
    _back.hidden = page == RBSettingsMain;
    _search.hidden = page != RBSettingsApplications;
    NSArray *titles = @[@"设置", @"绘图工具", @"悬浮球大小", @"悬浮球透明度", @"竖栏大小", @"App 管理", @"停用当前 App"];
    _title.text = titles[page];
    [_table reloadData];
    [_table setContentOffset:CGPointZero animated:NO];
    [self.view setNeedsLayout];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, _title);
    if (page == RBSettingsApplications && !_applications && !_loading) [self loadApplications];
}
- (void)goBack:(id)sender {
    if (_page == RBSettingsDisableConfirmation) [self cancelPendingConfirmation];
    [self showPage:_page == RBSettingsDisableConfirmation ? RBSettingsApplications : RBSettingsMain];
}
- (void)close:(id)sender {
    if (_page == RBSettingsDisableConfirmation) [self cancelPendingConfirmation];
    [self commitPendingChanges];
    if (self.closeHandler) self.closeHandler();
}
- (BOOL)accessibilityPerformEscape {
    if (_page != RBSettingsMain) [self goBack:nil];
    else [self close:nil];
    return YES;
}
- (NSArray<NSNumber *> *)toolTypes {
    return @[@(ACEDrawingToolTypePen), @(ACEDrawingToolTypeLine), @(ACEDrawingToolTypeArrow),
        @(ACEDrawingToolTypeRectagleStroke), @(ACEDrawingToolTypeRectagleFill), @(ACEDrawingToolTypeEllipseStroke),
        @(ACEDrawingToolTypeEllipseFill), @(ACEDrawingToolTypeEraser), @(ACEDrawingToolTypeDraggableText),
        @(ACEDrawingToolTypeTriangleStroke), @(ACEDrawingToolTypePentagonStroke), @(ACEDrawingToolTypeHexagoneStroke)];
}
- (NSArray<NSString *> *)mainTitles {
    NSMutableArray *titles = [@[[NSString stringWithFormat:@"工具：%@", [RBPrefs toolName]],
        @"悬浮球大小", @"悬浮球透明度", @"竖栏大小", @"App 管理"] mutableCopy];
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) [titles addObject:@"本次使用隐藏圆球"];
    return titles;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (_page) {
        case RBSettingsMain: return self.mainTitles.count;
        case RBSettingsTools: return [RBPrefs toolNames].count;
        case RBSettingsBallSize: case RBSettingsBallAlpha: return 3;
        case RBSettingsToolbarSize: return 1;
        case RBSettingsDisableConfirmation: return 3;
        case RBSettingsApplications: return MAX(1, (NSInteger)_filteredApplications.count) + (_errorMessage.length ? 1 : 0);
    }
    return 0;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat line = [UIFont preferredFontForTextStyle:UIFontTextStyleBody].lineHeight;
    if (_page == RBSettingsToolbarSize) return MAX(128, line * 2 + 88);
    if (_page == RBSettingsDisableConfirmation && indexPath.row == 0) {
        CGFloat width = MAX(1, tableView.bounds.size.width - 32);
        CGRect text = [[self confirmationText] boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
            options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]} context:nil];
        return MAX(100, ceil(text.size.height) + 24);
    }
    return MAX(_page == RBSettingsApplications ? 76 : 52, line * 2 + 16);
}
- (NSString *)confirmationText {
    return [NSString stringWithFormat:@"停用“%@”后，当前画板和悬浮球会关闭，未保存的绘图将丢失。", _pendingName ?: _pendingBundle ?: @"当前 App"];
}
- (BOOL)isBundleEnabled:(NSString *)bundle {
    id enabled = RBSetting(@"enabledApps", @[]);
    return [enabled isKindOfClass:NSArray.class] && [enabled containsObject:bundle];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSInteger appRow = path.row - (_errorMessage.length ? 1 : 0);
    BOOL isApplication = _page == RBSettingsApplications && appRow >= 0 && appRow < (NSInteger)_filteredApplications.count;
    NSString *reuseIdentifier = isApplication ? @"RBSettingsApplication" : nil;
    UITableViewCell *cell = reuseIdentifier ? [tableView dequeueReusableCellWithIdentifier:reuseIdentifier] : nil;
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    cell.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    CGFloat width = tableView.bounds.size.width;
    CGFloat height = [self tableView:tableView heightForRowAtIndexPath:path];
    if (isApplication) {
        NSDictionary *app = _filteredApplications[appRow];
        NSString *bundle = app[@"id"];
        NSString *name = app[@"name"] ?: bundle;
        cell.textLabel.text = name;
        cell.detailTextLabel.text = app[@"subtitle"] ?: bundle;
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        cell.textLabel.adjustsFontForContentSizeCategory = cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        cell.textLabel.textColor = UIColor.labelColor;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.lineBreakMode = cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        cell.imageView.image = RBApplicationIcon(bundle);
        UIView *target = cell.accessoryView;
        RBSettingsSwitch *toggle = (RBSettingsSwitch *)target.subviews.firstObject;
        if (!toggle) {
            target = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 59, 44)];
            toggle = [RBSettingsSwitch new];
            toggle.center = CGPointMake(29.5, 22);
            toggle.tintColor = UIColor.tertiaryLabelColor;
            toggle.onTintColor = UIColor.labelColor;
            toggle.thumbTintColor = UIColor.secondarySystemBackgroundColor;
            [toggle addTarget:self action:@selector(applicationChanged:) forControlEvents:UIControlEventValueChanged];
            [target addSubview:toggle];
            cell.accessoryView = target;
        }
        toggle.on = [self isBundleEnabled:bundle];
        toggle.enabled = !_saving;
        // Identity travels with the reusable control, independent of search results and error rows.
        toggle.bundleID = bundle;
        toggle.applicationName = name;
        toggle.accessibilityLabel = [NSString stringWithFormat:@"%@，%@，启用悬浮球", name, bundle];
        return cell;
    }
    if (_page == RBSettingsToolbarSize) {
        _scaleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, MAX(0, width - 32), height - 76)];
        _scaleLabel.numberOfLines = 0;
        _scaleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _scaleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _scaleLabel.adjustsFontForContentSizeCategory = YES;
        _scaleLabel.textColor = UIColor.labelColor;
        [cell.contentView addSubview:_scaleLabel];
        _scaleSlider = [[UISlider alloc] initWithFrame:CGRectMake(20, height - 64, MAX(0, width - 40), 44)];
        _scaleSlider.minimumValue = 0.6;
        _scaleSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _scaleSlider.maximumValue = 1.5;
        _scaleSlider.value = self.toolbarScale;
        _scaleSlider.tintColor = UIColor.labelColor;
        _scaleSlider.minimumTrackTintColor = UIColor.labelColor;
        _scaleSlider.maximumTrackTintColor = UIColor.tertiaryLabelColor;
        _scaleSlider.accessibilityLabel = @"全局竖栏大小";
        [_scaleSlider addTarget:self action:@selector(scaleChanged:) forControlEvents:UIControlEventValueChanged];
        [_scaleSlider addTarget:self action:@selector(scaleReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [cell.contentView addSubview:_scaleSlider];
        [self updateScaleLabel];
        return cell;
    }
    NSString *title;
    BOOL selected = NO;
    if (_page == RBSettingsMain) title = self.mainTitles[path.row];
    else if (_page == RBSettingsTools) {
        title = [RBPrefs toolNames][path.row];
        selected = [self.toolTypes[path.row] integerValue] == [RBPrefs tool];
    } else if (_page == RBSettingsBallSize) {
        title = @[@"小 · 44", @"中 · 56", @"大 · 64"][path.row];
        selected = fabs([RBPrefs ballSize] - [@[@44, @56, @64][path.row] doubleValue]) < 0.01;
    } else if (_page == RBSettingsBallAlpha) {
        title = @[@"60%", @"80%", @"100%"][path.row];
        selected = fabs([RBPrefs ballAlpha] - [@[@0.6, @0.8, @1][path.row] doubleValue]) < 0.01;
    } else if (_page == RBSettingsDisableConfirmation) {
        title = path.row == 0 ? self.confirmationText : (path.row == 1 ? @"取消，保留绘图" : @"停用并关闭画板");
    } else {
        BOOL errorRow = _errorMessage.length && path.row == 0;
        title = errorRow ? [_errorMessage stringByAppendingString:@"，轻点重试"] :
            (_loading ? @"正在加载 App…" : (_applications ? @"没有匹配的 App" : @"加载 App"));
    }
    RBChromeButton *button = [self buttonWithTitle:selected ? [title stringByAppendingString:@" ✓"] : title action:@selector(rowTapped:)];
    button.tag = path.row;
    button.frame = CGRectMake(8, 2, MAX(0, width - 16), height - 4);
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    button.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    if (_page == RBSettingsDisableConfirmation && path.row == 2)
        [button setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    if (_page == RBSettingsDisableConfirmation && path.row == 0) {
        button.enabled = NO;
        button.accessibilityTraits = UIAccessibilityTraitStaticText;
    }
    if (_page == RBSettingsApplications) button.enabled = !_saving && !_loading;
    [cell.contentView addSubview:button];
    return cell;
}
- (void)rowTapped:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (_page == RBSettingsMain) {
        switch (row) {
            case 0: [self showPage:RBSettingsTools]; return;
            case 1: [self showPage:RBSettingsBallSize]; return;
            case 2: [self showPage:RBSettingsBallAlpha]; return;
            case 3: [self showPage:RBSettingsToolbarSize]; return;
            case 4: [self showPage:RBSettingsApplications]; return;
            default:
                if (self.hideBallHandler) self.hideBallHandler();
                [self close:nil]; return;
        }
    } else if (_page == RBSettingsTools) {
        ACEDrawingToolType tool = (ACEDrawingToolType)[self.toolTypes[row] integerValue];
        [RBPrefs setTool:tool];
        if (self.toolChange) self.toolChange(tool);
    } else if (_page == RBSettingsBallSize) {
        [RBPrefs setBallSize:[@[@44, @56, @64][row] doubleValue]];
        [[RBFloating shared] applyPrefs];
    } else if (_page == RBSettingsBallAlpha) {
        [RBPrefs setBallAlpha:[@[@0.6, @0.8, @1][row] doubleValue]];
        [[RBFloating shared] applyPrefs];
    } else if (_page == RBSettingsDisableConfirmation) {
        if (row == 1) { [self cancelPendingConfirmation]; [self showPage:RBSettingsApplications]; return; }
        if (row == 2) { [self showPage:RBSettingsApplications]; [self savePendingApplication]; return; }
    } else if (_page == RBSettingsApplications) {
        if (_saving || _loading) return;
        if (RBSettingsAppRetryAllowed(_saving, _pendingBundle.length > 0, _errorMessage.length > 0)) [self savePendingApplication];
        else [self loadApplications];
        return;
    }
    [_table reloadData];
}
- (void)updateScaleLabel {
    _scaleLabel.text = [NSString stringWithFormat:@"全局竖栏大小：%.0f%%\n范围 60%%–150%%", self.toolbarScale * 100];
    _scaleSlider.accessibilityValue = [NSString stringWithFormat:@"%.0f%%", self.toolbarScale * 100];
}
- (void)scaleChanged:(UISlider *)slider {
    self.toolbarScale = slider.value;
    _scaleDirty = YES;
    [self updateScaleLabel];
    if (self.toolbarScaleChange) self.toolbarScaleChange(self.toolbarScale);
    // VoiceOver adjustments have no touch-up event.
    if (!slider.tracking) [self commitPendingChanges];
}
- (void)scaleReleased:(UISlider *)slider { [self commitPendingChanges]; }
- (void)commitPendingChanges {
    if (!_scaleDirty) return;
    _scaleDirty = NO;
    if (self.toolbarScaleCommit) self.toolbarScaleCommit(self.toolbarScale);
    else [RBPrefs setToolbarScale:self.toolbarScale];
}
- (void)viewWillDisappear:(BOOL)animated {
    [self commitPendingChanges];
    [super viewWillDisappear:animated];
}
- (void)loadApplications {
    if (_loading || _saving) return;
    _loading = YES;
    _errorMessage = nil;
    _pendingBundle = nil;
    [_table reloadData];
    __weak typeof(self) weakSelf = self;
    RBLoadApplications(^(NSArray<NSDictionary *> *apps, NSError *error) {
        RBSettingsPanel *panel = weakSelf;
        if (!panel) return;
        panel->_loading = NO;
        if (error) panel->_errorMessage = @"App 列表加载失败";
        else panel->_applications = apps ?: @[];
        [panel searchChanged:nil];
    });
}
- (void)searchChanged:(id)sender {
    _filteredApplications = RBFilterApplications(_applications ?: @[], _search.text ?: @"");
    [_table reloadData];
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }
- (void)cancelPendingConfirmation {
    _pendingBundle = nil;
    _pendingName = nil;
    _errorMessage = nil;
}
- (void)applicationChanged:(RBSettingsSwitch *)toggle {
    if (_saving || !toggle.bundleID.length) return;
    _pendingBundle = toggle.bundleID;
    _pendingName = toggle.applicationName;
    _pendingEnabled = toggle.on;
    _errorMessage = nil;
    if (RBSettingsAppChangeNeedsConfirmation(_pendingEnabled, [_pendingBundle isEqualToString:NSBundle.mainBundle.bundleIdentifier])) {
        [toggle setOn:YES animated:YES];
        [self showPage:RBSettingsDisableConfirmation];
    } else [self savePendingApplication];
}
- (void)savePendingApplication {
    if (_saving || !_pendingBundle.length) return;
    _saving = YES;
    _errorMessage = nil;
    [_table reloadData];
    __weak typeof(self) weakSelf = self;
    RBSetAppEnabled(_pendingBundle, _pendingEnabled, ^(BOOL saved, NSError *error) {
        RBSettingsPanel *panel = weakSelf;
        if (!panel) return;
        panel->_saving = NO;
        RBReloadSettings();
        if (!saved || error) {
            panel->_errorMessage = @"保存失败，已恢复当前设置";
            [panel->_table setContentOffset:CGPointZero animated:NO];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, panel->_errorMessage);
        } else {
            panel->_pendingBundle = nil;
            panel->_errorMessage = nil;
        }
        [panel refreshApplicationStates];
    });
}
- (void)refreshApplicationStates {
    if (self.isViewLoaded && _page == RBSettingsApplications) [_table reloadData];
}
- (void)contentSizeChanged:(NSNotification *)note { [_table reloadData]; }
@end
