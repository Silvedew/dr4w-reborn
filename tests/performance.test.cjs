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

test('ball visibility and per-app activation remain independent', () => {
  const settings = source('Shared/RBSettings.h');
  assert.match(settings, /RBSetting\(@"enabledApps", @\[\]\)/);
  assert.match(settings, /RBSettingBool\(@"showBall", NO\)/);
  assert.match(settings, /RBPolicyBall\(RBEnabledForBundle\(bundleID\)/);
  assert.match(source('Reborn/RBPrefs.m'), /return !RBBallForBundle\(bundleID\);/);
  const manager = source('Reborn/RBManager.m');
  assert.match(manager, /if \(\[RBPrefs isAppDisabled:[\s\S]*?&&\s*!\[\[RBManager shared\] isShowing\]\) return;/);
  assert.match(manager, /if \(!RBEnabledForBundle\(\[\[NSBundle mainBundle\] bundleIdentifier\]\)\) return NO;/);
});

test('settings save to a shared domain and notify running apps', () => {
  const settings = source('Shared/RBSettings.h');
  assert.match(settings, /CFPreferencesSetValue/);
  assert.match(settings, /if \(saved\) notify_post\(RB_SETTINGS_CHANGED\)/);
  const manager = source('Reborn/RBManager.m');
  assert.match(manager, /notify_register_dispatch\(RB_SETTINGS_CHANGED[\s\S]*?RBReloadSettings\(\)/);
  assert.match(manager, /notify_register_dispatch\("com.dsh.dr4wreborn.toggle"[\s\S]*?if \(RBMayPresent\(\)\) \[\[RBManager shared\] toggle\];/);
});

test('Settings entry, preference bundle, and dependency are included in packaging', () => {
  const workflow = source('.github/workflows/build.yml');
  const entry = source('Preferences/Dr4wReborn.plist');
  assert.match(entry, /\/var\/jb\/Library\/PreferenceBundles\/Dr4wRebornPrefs.bundle/);
  assert.match(source('Preferences/Info.plist'), /<string>RBRootListController<\/string>/);
  assert.match(workflow, /Preferences\/RBRootListController.m/);
  assert.match(workflow, /cp Dr4wRebornPrefs Preferences\/Info.plist/);
  assert.match(workflow, /Library\/PreferenceLoader\/Preferences/);
  assert.match(source('control'), /Depends:.*preferenceloader/);
  assert.match(workflow, /Depends:.*preferenceloader/);
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

test('preferences reuse their suite instead of allocating on every read', () => {
  const prefs = source('Reborn/RBPrefs.m');
  assert.match(prefs, /dispatch_once\(&once, \^\{ defaults = \[\[NSUserDefaults alloc\] initWithSuiteName:kDomain\]; \}\);/);
});
