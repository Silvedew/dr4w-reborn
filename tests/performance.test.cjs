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
  assert.match(manager, /RBStartLayoutPolling\(void\)\s*\{\s*if \(gLayoutTimer\) return;/);
  const springboard = manager.slice(manager.indexOf('if (RBIsSpringBoard()) {', manager.indexOf('static void RBBootstrap')));
  assert.ok(springboard.indexOf('return;') < springboard.indexOf('RBStartLayoutPolling();'));
});

test('volume fallback yields to fast polling and fast polling expires after one second', () => {
  const manager = source('Reborn/RBManager.m');
  assert.match(manager, /if \(gFastTimer\) return;\s*RBPollVolume\(\);/);
  assert.match(manager, /1\.0 \* NSEC_PER_SEC[\s\S]*?if \(gen != gFastGen\) return;[\s\S]*?\[gFastTimer invalidate\];/);
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
