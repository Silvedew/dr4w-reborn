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
  const springboard = manager.slice(manager.indexOf('if (RBIsSpringBoard()) {', manager.indexOf('static void RBBootstrap')));
  assert.ok(springboard.indexOf('return;') < springboard.indexOf('RBStartLayoutPolling();'));
});

test('SpringBoard never polls private audio or frontmost-app interfaces', () => {
  const manager = source('Reborn/RBManager.m');
  assert.doesNotMatch(manager, /RBPollVolume|RBStartFastPolling|objc_msgSend|RBOtherAppFrontmost|SBFrontmostApplicationDisplayIdentifier/);
  const bootstrap = manager.slice(manager.indexOf('static void RBBootstrap'));
  const springboard = bootstrap.slice(bootstrap.indexOf('if (RBIsSpringBoard())'), bootstrap.indexOf('/* every app:'));
  assert.doesNotMatch(springboard, /scheduledTimer|dispatch_source_create/);
  assert.match(springboard, /AVSystemController_SystemVolumeDidChangeNotification/);
});

test('volume notifications are validated and handled on the main queue', () => {
  const manager = source('Reborn/RBManager.m');
  const callback = manager.slice(manager.indexOf('static void RBVolumeNote'), manager.indexOf('#pragma mark - startup'));
  assert.match(callback, /isKindOfClass:\[NSNumber class\]/);
  assert.match(callback, /dispatch_async\(dispatch_get_main_queue\(\), \^\{ RBHandleVolume\(volume\); \}\)/);
  assert.match(manager, /!isfinite\(v\) \|\| v < 0.0f \|\| v > 1.0f/);
});

test('locking resets the trigger and closes the drawing window', () => {
  const manager = source('Reborn/RBManager.m');
  assert.match(manager, /static BOOL\s+gDeviceLocked = YES;/);
  assert.match(manager, /com.apple.springboard.lockstate/);
  assert.match(manager, /gDeviceLocked = state != 0;[\s\S]*?gBuffer = @"";[\s\S]*?gLastPress = 0;[\s\S]*?if \(gDeviceLocked\) \[\[RBManager shared\] dismiss\];/);
  assert.match(manager, /if \(RBIsSpringBoard\(\)\) return !gDeviceLocked;/);
  assert.match(manager, /if \(self->_window != w\) return;\s*if \(!RBMayPresent\(\)\) return;/);
});

test('balls default to hidden, and enabling is stored as an explicit per-app opt-in', () => {
  const prefs = source('Reborn/RBPrefs.m');
  const policy = prefs.slice(prefs.indexOf('+ (BOOL)isAppDisabled:'));
  assert.match(policy, /if \(!bundleID\) return YES;/);
  assert.match(policy, /arrayForKey:@"enabledBallApps"/);
  assert.match(policy, /return !\[enabled containsObject:bundleID\];/);
  assert.match(policy, /if \(disabled\)\s*\{\s*\[list removeObject:bundleID\];\s*\} else \{\s*if \(!\[list containsObject:bundleID\]\) \[list addObject:bundleID\];/);
  assert.doesNotMatch(policy, /@"disabledApps"/);
  const manager = source('Reborn/RBManager.m');
  assert.match(manager, /if \(\[RBPrefs isAppDisabled:[\s\S]*?&&\s*!\[\[RBManager shared\] isShowing\]\) return;/);
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
