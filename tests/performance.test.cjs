// Source guards for regressions; UIKit behavior still requires an iPad smoke test.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const source = file => readFileSync(join(__dirname, '..', file), 'utf8');

test('backgrounding invalidates the layout timer and foregrounding restarts it', () => {
  const manager = source('Reborn/RBManager.m');
  assert.match(manager, /RBStopLayoutPolling\(void\)[\s\S]*?\[gLayoutTimer invalidate\];\s*gLayoutTimer = nil;/);
  assert.match(manager, /UIApplicationDidEnterBackgroundNotification[\s\S]*?RBStopLayoutPolling\(\);/);
  assert.match(manager, /UIApplicationDidBecomeActiveNotification[\s\S]*?RBStartLayoutPolling\(\);/);
  assert.match(manager, /if \(gLayoutTimer\) return;/);
  assert.match(manager, /RBStartLayoutPolling\(void\)\s*\{\s*if \(RBIsSpringBoard\(\)\) return;/);
});

test('SpringBoard never polls private audio or frontmost-app interfaces', () => {
  const manager = source('Reborn/RBManager.m');
  assert.doesNotMatch(manager, /RBPollVolume|RBStartFastPolling|objc_msgSend|RBOtherAppFrontmost|SBFrontmostApplicationDisplayIdentifier/);
  const bootstrap = manager.slice(manager.indexOf('static void RBBootstrap'));
  const springboard = bootstrap.slice(bootstrap.indexOf('if (RBIsSpringBoard())'), bootstrap.indexOf('/* every app:'));
  assert.doesNotMatch(springboard, /scheduledTimer|dispatch_source_create/);
  assert.match(springboard, /RBInstallVolumeHooks/);
});

test('button hooks check signatures, preserve volume handling, and dispatch on the main queue', () => {
  const hooks = source('Reborn/RBSystemHooks.m');
  assert.match(hooks, /method_getNumberOfArguments\(method\) != 2/);
  assert.match(hooks, /strcmp\(result, @encode\(void\)\) == 0/);
  assert.match(hooks, /gOriginalUp\(self, command\);\s*dispatch_async\(dispatch_get_main_queue\(\)/);
  assert.match(hooks, /gOriginalDown\(self, command\);\s*dispatch_async\(dispatch_get_main_queue\(\)/);
  assert.doesNotMatch(hooks, /outputVolume|setVolume|AVSystemController/);
});

test('locking resets the trigger and closes the drawing window', () => {
  const manager = source('Reborn/RBManager.m');
  assert.match(manager, /com.apple.springboard.lockstate/);
  assert.match(manager, /gVolumeSequence = \(RBVolumeSequence\)\{0\};\s*if \(RBDeviceIsLocked\(\)\) \[\[RBManager shared\] dismiss\];/);
  assert.match(manager, /if \(RBIsSpringBoard\(\)\) return !RBDeviceIsLocked\(\) && RBHomeIsVisible\(\);/);
  assert.match(source('Reborn/RBSystemHooks.m'), /return \[manager isUILocked\];/);
  assert.match(manager, /if \(self->_window != w\) return;\s*if \(!RBMayPresent\(\)\) return;/);
});

test('enabling an app shows its ball without legacy visibility overrides', () => {
  const settings = source('Shared/RBSettings.h');
  assert.match(settings, /RBSetting\(@"enabledApps", @\[\]\)/);
  assert.match(settings, /RBBallForBundle[\s\S]*?return RBEnabledForBundle\(bundleID\);/);
  assert.doesNotMatch(settings, /@"showBall"|@"ballOverrides"/);
  assert.match(source('Reborn/RBPrefs.m'), /return !RBBallForBundle\(bundleID\);/);
  const manager = source('Reborn/RBManager.m');
  assert.match(manager, /if \(\[RBPrefs isAppDisabled:[\s\S]*?&&\s*!\[\[RBManager shared\] isShowing\]\) return;/);
  assert.match(manager, /if \(!RBEnabledForBundle\(\[\[NSBundle mainBundle\] bundleIdentifier\]\)\) return NO;/);
});

test('temporary hiding survives refresh and resets only on foreground entry or re-enabling', () => {
  const floating = source('Reborn/RBFloating.m');
  const show = floating.slice(floating.indexOf('- (void)show'), floating.indexOf('- (void)hide'));
  assert.doesNotMatch(show, /_userHidden = NO/);
  assert.match(show, /RBPolicyBall\(!\[self disabledHere\], _userHidden\)/);
  assert.match(floating, /restoreForForeground\s*\{\s*_userHidden = NO;/);
  const manager = source('Reborn/RBManager.m');
  assert.match(manager, /if \(enabled && !wasEnabled\)[\s\S]*?restoreForForeground/);
  assert.match(manager, /UISceneDidActivateNotification[\s\S]*?restoreForForeground/);
  assert.match(manager, /UISceneDidDisconnectNotification/);
  assert.match(floating, /RBPolicyCanHostWindow\(scene != nil, \[UIApplication sharedApplication\].connectedScenes.count\)/);
  assert.match(floating, /if \(_win && _win.windowScene == scene\) return;/);
  assert.match(floating, /if \(scene\) _win.windowScene = scene;/);
  assert.doesNotMatch(source('Reborn/RBPrefs.m'), /setAppDisabled|@"ballOverrides"/);
});

test('settings save to a shared domain and notify running apps', () => {
  const settings = source('Shared/RBSettings.h');
  assert.match(settings, /return RBStoreSetting\(key, value\)/);
  assert.match(settings, /stringByAppendingString:@"\/ReloadPrefs"/);
  assert.match(settings, /RBObserveSnapshot\(callback\)/);
  assert.match(source('Shared/RBSettingsStore.m'), /registerPreferenceChangeBlock:\^\{\s*dispatch_async\(dispatch_get_main_queue\(\)/);
  assert.doesNotMatch(settings, /CFPreferencesCopyValue|CFPreferencesSynchronize|initWithSuiteName/);
  const manager = source('Reborn/RBManager.m');
  assert.match(manager, /RBObserveSettings\(\^\{/);
  assert.doesNotMatch(manager, /notify_register_dispatch\(RB_SETTINGS_CHANGED/);
  assert.match(manager, /notify_register_dispatch\("com.dsh.dr4wreborn.toggle"[\s\S]*?BOOL allowed = RBMayPresent\(\);[\s\S]*?if \(allowed\) \[\[RBManager shared\] toggle\];/);
});

test('Settings entry, preference bundle, and dependency are included in packaging', () => {
  const workflow = source('.github/workflows/build.yml');
  const entry = source('Preferences/Dr4wReborn.plist');
  assert.match(entry, /\/var\/jb\/Library\/PreferenceBundles\/Dr4wRebornPrefs.bundle/);
  assert.match(entry, /<key>detail<\/key><string>RBRootListController<\/string>/);
  assert.match(source('Preferences/Info.plist'), /<string>RBRootListController<\/string>/);
  assert.match(workflow, /Preferences\/RBRootListController.m/);
  assert.match(workflow, /cp Dr4wRebornPrefs Preferences\/Info.plist/);
  assert.match(workflow, /Library\/PreferenceLoader\/Preferences/);
  assert.match(source('control'), /Depends:.*preferenceloader/);
  assert.match(workflow, /Depends:.*preferenceloader/);
  assert.match(source('control'), /ws.hbang.common \(>= 2.0\)/);
  assert.match(workflow, /ws.hbang.common \(>= 2.0\)/);
  assert.match(workflow, /cephei_sdk_2.0.zip/);
  assert.match(workflow, /665758f996b333e8e58594af9950fc8e3ffe7c3c4078f49f66cadeaa162ef154/);
  assert.match(workflow, /-framework Cephei -Wl,-rpath,\/var\/jb\/Library\/Frameworks/);
  assert.match(entry, /<key>icon<\/key><string>\/var\/jb\/Library\/PreferenceLoader\/Preferences\/Dr4wReborn.png<\/string>/);
  assert.match(workflow, /swift scripts\/generate-settings-icons.swift settings-icons/);
  assert.match(workflow, /cp settings-icons\/Dr4wReborn\*\.png/);
  assert.match(source('scripts/generate-settings-icons.swift'), /Shared\/RBIconStyle.h/);
  assert.match(source('Reborn/RBFloating.m'), /systemImageNamed:@RB_PENCIL_SYMBOL/);
});

test('Settings pages publish rows to PSListController and clear their cache on reload', () => {
  const controller = source('Preferences/RBRootListController.m');
  assert.match(controller, /self.rbSpecifiers = \[specifiers mutableCopy\];\s*\[super setSpecifiers:self.rbSpecifiers\];/);
  assert.match(controller, /self.rbSpecifiers = nil;\s*\[super reloadSpecifiers\];/);
  assert.equal((controller.match(/\[self publishSpecifiers:/g) || []).length, 2);
});

test('inactive apps cannot restore the floating window', () => {
  const floating = source('Reborn/RBFloating.m');
  const show = floating.slice(floating.indexOf('- (void)show'), floating.indexOf('- (void)hide'));
  assert.ok(show.indexOf('UIApplicationStateActive') < show.indexOf('[self buildIfNeeded]'));
  assert.match(show, /if \(\[\[RBManager shared\] isShowing\]\) \{ _win.hidden = YES; return; \}/);
});

test('drawing reuses a renderer, rebuilding it on resize and skipping empty bounds', () => {
  const drawing = source('Engine/ACEDrawingView.m');
  const cache = drawing.slice(drawing.indexOf('- (void)updateCacheImage:'), drawing.indexOf('- (UIImage *)drawings'));
  assert.match(cache, /if \(CGRectIsEmpty\(self.bounds\)\) return;/);
  assert.match(cache, /!self.cacheRenderer \|\| !CGSizeEqualToSize\(self.cacheRendererSize, self.bounds.size\)/);
  assert.match(cache, /self.cacheRendererSize = self.bounds.size;/);
  assert.match(cache, /imageWithActions:/);
  assert.doesNotMatch(cache, /UIGraphicsBeginImageContext/);
  assert.match(cache, /for \(id<ACEDrawingTool> tool in self.pathArray\)/);
  assert.match(cache, /\[self.currentTool draw\]/);
});

test('drawing preferences use the same sandbox-compatible backend as activation settings', () => {
  const prefs = source('Reborn/RBPrefs.m');
  assert.match(prefs, /RBSetting\(@"toolIndex"/);
  assert.match(prefs, /RBWriteSetting\(@"toolIndex"/);
  assert.doesNotMatch(prefs, /NSUserDefaults|CFPreferences|HBPreferences|\[self defaults\]/);
});

test('sandbox settings use event-driven snapshots and bounded worker-queue transport', () => {
  const store = source('Shared/RBSettingsStore.m');
  const refresh = store.slice(store.indexOf('void RBRefreshSettings'), store.indexOf('void RBObserveSnapshot'));
  assert.match(refresh, /dispatch_async\(RBSettingsQueue\(\),/);
  assert.match(refresh, /if \(!values\)[\s\S]*?RBBridgeRequest/);
  assert.match(refresh, /if \(snapshot\) gSnapshot = snapshot/);
  assert.match(refresh, /if \(gRefreshPending\)/);
  assert.match(store, /0\.15, 0\.25, kCFRunLoopDefaultMode/);
  assert.match(store, /dispatch_group_wait\(gCepheiRead, dispatch_time\(DISPATCH_TIME_NOW, 250 \* NSEC_PER_MSEC\)\)/);
  assert.match(store, /@"cy:"/);
  assert.match(store, /@"lh:"/);
  assert.match(store, /request\[@"domain"\] isEqual:RB_SETTINGS_DOMAIN/);
  assert.match(store, /data.length > 256 \* 1024/);
  const writable = store.slice(store.indexOf('static BOOL RBWritableDrawingKey'), store.indexOf('static NSArray'));
  assert.doesNotMatch(writable, /enabledApps|@"enabled"|homeEnabled/);
  assert.doesNotMatch(store, /scheduledTimer|dispatch_after|dictionaryWithContentsOfFile/);
  assert.match(source('Reborn/RBManager.m'), /if \(RBIsSpringBoard\(\)\) RBStartSettingsService\(\);/);
});

test('injection uses bundle alternatives and initializes UIKit only after reaching the main queue', () => {
  const filter = source('Dr4wReborn.plist');
  assert.match(filter, /<key>Mode<\/key><string>Any<\/string>/);
  for (const bundle of ['com.apple.springboard', 'com.apple.UIKit', 'com.apple.UIKitCore'])
    assert.ok(filter.includes(`<string>${bundle}</string>`));
  assert.doesNotMatch(filter, /<key>Classes<\/key>/);
  const manager = source('Reborn/RBManager.m');
  const bootstrap = manager.slice(manager.indexOf('static void RBBootstrap'));
  assert.doesNotMatch(bootstrap.slice(0, bootstrap.indexOf('dispatch_after')), /NSClassFromString/);
  assert.match(bootstrap, /dispatch_get_main_queue\(\)[\s\S]*?bundle.infoDictionary\[@"NSExtension"\][\s\S]*?dispatch_once\(&once/);
  for (const event of ['loaded', 'initialized', 'toggle.received']) assert.ok(manager.includes(`@"${event}"`));
  assert.match(source('Shared/RBDiagnostics.h'), /RB_BUILD_VERSION/);
});

test('native chrome adapts its material and press feedback to accessibility settings', () => {
  const chrome = source('Reborn/RBChrome.m');
  assert.match(chrome, /UIBlurEffectStyleSystemMaterial/);
  assert.match(chrome, /UIAccessibilityIsReduceTransparencyEnabled/);
  assert.match(chrome, /UIAccessibilityReduceTransparencyStatusDidChangeNotification/);
  assert.match(chrome, /UIAccessibilityContrastHigh/);
  assert.match(chrome, /UIAccessibilityIsReduceMotionEnabled/);
  assert.match(chrome, /UIViewAnimationOptionBeginFromCurrentState \| UIViewAnimationOptionAllowUserInteraction/);
  const controller = source('Reborn/RBController.m');
  assert.match(controller, /viewDidLayoutSubviews[\s\S]*?safeAreaInsets[\s\S]*?RBLayoutToolbar/);
  assert.match(controller, /_barScroll.delaysContentTouches = NO/);
  assert.match(controller, /b.accessibilityLabel = label/);
  assert.doesNotMatch(controller, /SystemThinMaterialLight|colorWithWhite:0\.10/);
  assert.match(source('Reborn/RBFloating.m'), /initWithFrame:_win.bounds usesMaterial:NO/);
});

test('floating toolbar moves only from its fixed handle and saves per-app position at gesture end', () => {
  const controller = source('Reborn/RBController.m');
  assert.match(controller, /\[_dragHandle addGestureRecognizer:_barPan\]/);
  assert.doesNotMatch(controller, /\[_bar(?:Scroll)? addGestureRecognizer:_barPan\]/);
  assert.match(controller, /_toolbarPosition = RBToolbarPositionForApp\(NSBundle.mainBundle.bundleIdentifier\)/);
  assert.match(controller, /if \(gesture.state == UIGestureRecognizerStateEnded\) \[self saveToolbarPosition\]/);
  assert.match(controller, /gesture translationInView:self.view/);
  assert.match(controller, /RBToolbarPositionForOrigin/);
  assert.match(controller, /_barScroll.frame = CGRectMake\(0, RBToolbarScrollTop/);
  const movement = controller.slice(controller.indexOf('- (void)placeToolbarAt:'), controller.indexOf('#pragma mark - actions'));
  assert.doesNotMatch(movement, /RBWriteSetting|setFloatCenter|NSUserDefaults|animateWithDuration/);
  assert.equal((controller.match(/initWithName:@"向[上下左右]移动"/g) || []).length, 4);
  assert.match(source('Shared/RBIconStyle.h'), /RB_SETTINGS_SYMBOL "gearshape"/);
  assert.match(source('Reborn/RBFloating.m'), /_btn.tintColor = UIColor.labelColor/);
  assert.doesNotMatch(source('Preferences/RBRootListController.m'), /systemBlueColor/);
});

test('vertical stroke-width control updates locally and commits after interaction', () => {
  const popover = source('Reborn/RBWidthPopover.m');
  assert.match(popover, /_slider.minimumValue = 1/);
  assert.match(popover, /_slider.maximumValue = 30/);
  const change = popover.slice(popover.indexOf('- (void)widthChanged:'), popover.indexOf('- (void)commitWidth:'));
  assert.match(change, /_change\(width\)/);
  assert.doesNotMatch(change, /_commit\(|RBWriteSetting|RBPrefs/);
  assert.match(popover, /viewWillDisappear:[\s\S]*?\[self commitWidth:nil\]/);
  assert.match(popover, /accessibilityIncrement[\s\S]*?self.value \+ 1/);
  assert.match(popover, /CGAffineTransformMakeRotation\(-M_PI_2\)/);
  assert.match(popover, /CGContextRotateCTM\(context.CGContext, M_PI_2\)/);
  assert.match(popover, /_scroll.scrollEnabled = NO/);
  assert.match(popover, /cancelTrackingWithEvent:[\s\S]*?_scroll.scrollEnabled = _restoreScrolling/);
  assert.match(source('Reborn/RBController.m'), /@\[_close, _clear, _brush, _undo, _gear\]/);
  assert.match(source('Reborn/RBPrefs.m'), /RBSetting\(@"strokeWidth", nil\)/);
  assert.match(source('Shared/RBSettingsStore.m'), /@"strokeWidth"/);
});

test('brush panel shares toolbar chrome without a second material, arrow or width heading', () => {
  const brush = source('Reborn/RBBrushPopover.m');
  const width = source('Reborn/RBWidthPopover.m');
  const controller = source('Reborn/RBController.m');
  assert.match(brush, /popoverBackgroundViewClass = RBBrushBackgroundView.class/);
  assert.match(brush, /wantsDefaultContentAppearance\s*\{ return NO; \}/);
  assert.equal((brush.match(/\[\[RBChromeSurface alloc\]/g) || []).length, 1);
  assert.match(brush, /self.view.backgroundColor = UIColor.clearColor/);
  assert.match(controller, /popover.popoverPresentationController.permittedArrowDirections = 0/);
  assert.match(brush, /_picker.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny/);
  assert.doesNotMatch(width, /_title|heading|\.text = @"粗细"/);
  assert.match(width, /accessibilityLabel = @"画笔粗细"/);
  assert.match(width, /CGSizeMake\(60, 184\)/);
  assert.match(width, /CGFloat inset = MIN\(24, self.bounds.size.width \/ 4\)/);
  assert.match(controller, /_dragHandle.frame = CGRectMake\(RBToolbarPadding, layout.height - RBToolbarPadding - RBToolbarHandle/);
  assert.match(controller, /layout.height - RBToolbarScrollTop - RBToolbarGap - RBToolbarHandle - RBToolbarPadding/);
});

test('floating ball stays transparent and uses rotation-safe placement and dragging', () => {
  const floating = source('Reborn/RBFloating.m');
  assert.match(floating, /_win.opaque = NO/);
  assert.match(floating, /vc.view.opaque = NO/);
  assert.match(floating, /_win.clipsToBounds = YES/);
  assert.match(floating, /vc.view.clipsToBounds = YES/);
  assert.doesNotMatch(floating, /_win.frame/);
  assert.match(floating, /_win.bounds = CGRectMake\(0, 0, size, size\)/);
  assert.match(floating, /convertPoint:center fromCoordinateSpace:\[self hostSpace\]/);
  assert.match(floating, /CGSizeApplyAffineTransform/);
  assert.match(floating, /_win.center = CGPointMake\(_win.center.x \+ delta.width, _win.center.y \+ delta.height\)/);
  assert.match(floating, /if \(_win.windowScene\) return _win.windowScene.coordinateSpace/);
  assert.match(floating, /window.windowLevel == UIWindowLevelNormal && window.rootViewController/);
  assert.match(floating, /return _win.screen.coordinateSpace/);
  const transition = floating.slice(floating.indexOf('- (void)viewWillTransitionToSize:'), floating.indexOf('@implementation RBFloating {'));
  assert.match(transition, /animateAlongsideTransition:[\s\S]*?\[self.owner applyPrefs\][\s\S]*?completion:[\s\S]*?\[self.owner applyPrefs\]/);
  assert.doesNotMatch(transition, /hidden =|transform =|makeKey/);
  assert.match(floating, /viewDidLayoutSubviews[\s\S]*?\[self.owner layoutBall\]/);
  const pan = floating.slice(floating.indexOf('- (void)panned:'));
  assert.match(pan, /convertPoint:CGPointZero fromCoordinateSpace:_win/);
  assert.match(pan, /convertPoint:t fromCoordinateSpace:_win/);
  assert.match(pan, /end.x - start.x/);
  assert.match(pan, /end.y - start.y/);
  assert.match(floating, /RBClampFloatingOrigin/);
  assert.match(source('.github/workflows/build.yml'), /tests\/floating_layout_test.c/);
});

test('compact brush popover uses centered icon slots and edits only the selected slot', () => {
  const brush = source('Reborn/RBBrushPopover.m');
  const pick = brush.slice(brush.indexOf('- (void)pick:'), brush.indexOf('- (void)editColor:'));
  assert.match(pick, /_colorChange\(_color\)/);
  assert.doesNotMatch(pick, /dismissViewController/);
  assert.match(pick, /RBBrushTapEdits\(_selectedSlot, sender.tag\)/);
  assert.match(brush, /addChildViewController:_widthController/);
  assert.match(brush, /_scroll.contentSize/);
  assert.match(brush, /BOOL selected = _selectedSlot == \(NSInteger\)i/);
  assert.match(brush, /\(width - RBBrushColorTarget\) \/ 2/);
  assert.doesNotMatch(brush, /setTitle:|更多颜色|_heading|_colorHeading/);
  assert.match(brush, /picker.popoverPresentationController.passthroughViews = @\[\]/);
  assert.equal((brush.match(/return UIModalPresentationNone;/g) || []).length, 2);
  assert.match(brush, /_picker.popoverPresentationController.delegate = self/);
  assert.match(brush, /presentationControllerDidDismiss:[\s\S]*?\[self commitColor\]/);
  const preview = brush.slice(brush.indexOf('- (void)colorPickerViewControllerDidSelectColor:'), brush.indexOf('- (void)colorPickerViewControllerDidFinish:'));
  assert.doesNotMatch(preview, /RBSaveBrushColor|commitColor/);
  const controller = source('Reborn/RBController.m');
  assert.doesNotMatch(controller, /RBColorPaletteVC|showWidthsFromButton|colorTapped/);
  assert.doesNotMatch(controller, /setCustomColor:color/);
  assert.match(controller, /updateAvailableSize:/);
  assert.match(controller, /popover.popoverPresentationController.passthroughViews = @\[\]/);
});
