const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const read = path => fs.readFileSync(path, 'utf8');
const controller = read('Reborn/RBController.m');
const manager = read('Reborn/RBManager.m');
const label = read('Engine/ACEDrawingLabelView.m');
const drawing = read('Engine/ACEDrawingView.m');
const transport = read('Shared/RBScreenshotTransport.m');
const service = read('Reborn/RBScreenshotService.m');
const section = (source, start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));

test('screenshot keeps annotations, disables touch, waits for keyboard and two visible frames', () => {
  const start = section(controller, '- (void)screenshotTapped:', '- (void)screenshotKeyboardSettled:');
  assert.match(controller, /_barButtons = @\[_close, _clear, _brush, _undo, _screenshot, _gear\]/);
  assert.match(start, /RBScreenshotBegin/);
  assert.match(start, /_drawView\.userInteractionEnabled = NO/);
  assert.match(start, /beginSystemScreenshot/);
  assert.match(start, /_screenshotWaitingForKeyboard = _keyboardTransitioning \|\| \[self screenshotKeyboardIsVisible\]/);
  assert.match(controller, /if \(\+\+_screenshotFrames < 2\) return/);
  assert.doesNotMatch(start, /\b(clear|prepareForSnapshot|hideTextToolHandles|undoLatestStep)\b/);
  assert.match(controller, /willSend:\^BOOL[\s\S]*?screenshotSessionIsCurrent:generation[\s\S]*?sent = true/);
});

test('failure restores text composition, selection, handles, opacity, keyboard and interactions', () => {
  const begin = section(label, '- (BOOL)beginSystemScreenshot', '- (void)endSystemScreenshotRestoringFocus:');
  const restore = section(label, '- (void)endSystemScreenshotRestoringFocus:', '- (void)hideEditingHandles');
  for (const value of ['text', 'selection', 'marked', 'firstResponder', 'inputView', 'accessoryView', 'closeHidden', 'rotateHidden', 'borderHidden', 'opacity'])
    assert.match(begin, new RegExp(`state\\.${value} =`));
  assert.match(begin, /field\.inputView = \[\[UIView alloc\] initWithFrame:CGRectZero\]/);
  assert.doesNotMatch(begin, /resignFirstResponder|hideEditingHandles|removeFromSuperview/);
  assert.match(restore, /field\.attributedText = state\.text/);
  assert.match(restore, /setMarkedText:[\s\S]*?selectedRange:selected/);
  assert.match(restore, /field\.selectedTextRange = selection/);
  assert.match(controller, /restoreScreenshotPresentationWithFocus:YES/);
  assert.match(controller, /_drawView\.userInteractionEnabled = _screenshotDrawingInteraction/);
  const draw = section(drawing, '- (BOOL)beginSystemScreenshot', '- (void)hideTextToolHandles');
  assert.doesNotMatch(draw, /removeAllObjects|clear\]|hideHandle\]|prepareForSnapshot/);
});

test('cancelled generations cannot send or close a later drawing session', () => {
  assert.match(controller, /RBScreenshotCancel\(&_screenshotSession\)/);
  assert.match(controller, /if \(!\[controller screenshotSessionIsCurrent:generation\]\) return/);
  assert.match(manager, /cancelPendingScreenshot/);
  assert.match(manager, /UISceneWillDeactivateNotification, UISceneDidDisconnectNotification/);
  assert.match(manager, /UIApplicationWillResignActiveNotification[\s\S]*?\[\[RBManager shared\] dismiss\]/);
  assert.match(controller, /screenshotHostDidDeactivate:[\s\S]*?notification\.object == self\.view\.window\.windowScene\) \[self cancelPendingScreenshot\]/);
  assert.match(controller, /result == RBScreenshotSucceeded[\s\S]*?dismissFromUser/);
  assert.match(transport, /if \(current\) current = willSend && willSend\(\)/);
});

test('only dedicated audit transport can invoke SpringBoard capture, without resend', () => {
  assert.match(transport, /MACH_RCV_TRAILER_ELEMENTS\(MACH_RCV_TRAILER_AUDIT\)/);
  assert.match(transport, /msgh_audit\.val\[5\][\s\S]*?msgh_audit\.val\[7\]/);
  assert.match(transport, /RBScreenshotClaim\(replay\.entries/);
  assert.equal((transport.match(/kern_return_t sent = mach_msg/g) || []).length, 1);
  assert.match(transport, /mach_msg\(&request.header, MACH_SEND_MSG \| MACH_SEND_TIMEOUT \| MACH_SEND_INTERRUPT/);
  assert.match(service, /RBScreenshotIdentityMatches\(sender, query\)/);
  assert.match(service, /@encode\(int\)[\s\S]*?@encode\(NSInteger\)/);
  assert.match(service, /RBDeviceIsLocked\(\)[\s\S]*?RBScreenshotAuthorize\(sender, &provider\)/);
  assert.match(service, /gCapturePending \|\| !RBCaptureSupported/);
  assert.match(service, /systemUptime >= deadline[\s\S]*?RBScreenshotRejected[\s\S]*?objc_msgSend\)\(UIApplication.sharedApplication, NSSelectorFromString\(@"takeScreenshot"\)\)/);
  assert.doesNotMatch(read('Shared/RBSettingsStore.m'), /takeScreenshot|RBTakeLocalSystemScreenshot|RBInvokeSystemScreenshot/);
});
