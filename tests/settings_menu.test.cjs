const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const source = file => readFileSync(join(__dirname, '..', file), 'utf8');

function methodBody(text, signature) {
  const start = text.indexOf(signature);
  assert.notEqual(start, -1, `missing method ${signature}`);
  const open = text.indexOf('{', start);
  let depth = 0;
  for (let index = open; index < text.length; index++) {
    if (text[index] === '{') depth++;
    if (text[index] === '}' && --depth === 0) return text.slice(open + 1, index);
  }
  assert.fail(`unterminated method ${signature}`);
}

test('settings main menu exposes only settings entries and maps each row correctly', () => {
  const panel = source('Reborn/RBSettingsPanel.m');
  const header = source('Reborn/RBSettingsPanel.h');
  const mainTitles = methodBody(panel, '- (NSArray<NSString *> *)mainTitles');
  const literals = [...mainTitles.matchAll(/@"([^"]*)"/g)].map(match => match[1])
    .filter(value => value !== 'com.apple.springboard');
  assert.deepEqual(literals, [
    '工具：%@', '悬浮球大小', '悬浮球透明度', '竖栏大小', 'App 管理', '本次使用隐藏圆球',
  ]);
  assert.match(mainTitles, /if \(!\[NSBundle\.mainBundle\.bundleIdentifier isEqualToString:@"com\.apple\.springboard"\]\)\s*\[titles addObject:@"本次使用隐藏圆球"\]/);
  assert.doesNotMatch(header + panel, /brushHandler|clearHandler|画笔设置|一键清屏/);

  const rowTapped = methodBody(panel, '- (void)rowTapped:(UIButton *)sender');
  const switchStart = rowTapped.indexOf('switch (row)');
  const switchOpen = rowTapped.indexOf('{', switchStart);
  let depth = 0;
  let switchEnd = -1;
  for (let index = switchOpen; index < rowTapped.length; index++) {
    if (rowTapped[index] === '{') depth++;
    if (rowTapped[index] === '}' && --depth === 0) { switchEnd = index; break; }
  }
  const rowSwitch = rowTapped.slice(switchOpen + 1, switchEnd);
  const routes = [...rowSwitch.matchAll(/case (\d+): \[self showPage:(RBSettings\w+)\]; return;/g)]
    .map(match => [Number(match[1]), match[2]]);
  assert.deepEqual(routes, [
    [0, 'RBSettingsTools'], [1, 'RBSettingsBallSize'], [2, 'RBSettingsBallAlpha'],
    [3, 'RBSettingsToolbarSize'], [4, 'RBSettingsApplications'],
  ]);
  assert.match(rowSwitch, /default:\s*if \(self\.hideBallHandler\) self\.hideBallHandler\(\);\s*\[self close:nil\]; return;/);
  assert.doesNotMatch(rowSwitch, /clear|brush/);
});

test('settings panel labels are shortened and only app deactivation stays destructive', () => {
  const panel = source('Reborn/RBSettingsPanel.m');
  const pageTitle = methodBody(panel, '- (void)showPage:(RBSettingsPage)page');
  assert.match(pageTitle, /@\[@"设置", @"绘图工具"/);
  assert.doesNotMatch(panel, /绘图设置|绘画设置/);
  assert.match(panel, /_back\.accessibilityLabel = _back\.largeContentTitle = @"返回设置"/);
  assert.match(panel, /_close\.accessibilityLabel = _close\.largeContentTitle = @"关闭设置"/);
  const titleForRow = methodBody(panel, '- (NSString *)titleForRow:(NSInteger)row selected:(BOOL *)selected');
  assert.match(titleForRow, /_page == RBSettingsDisableConfirmation[\s\S]*?row == 1 \? @"取消，保留绘图" : @"停用并关闭画板"/);
  const cell = methodBody(panel, '- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path');
  assert.doesNotMatch(cell, /_page == RBSettingsMain && path\.row/);
  assert.match(cell, /_page == RBSettingsDisableConfirmation && path\.row == 2[\s\S]*?UIColor\.systemRedColor/);
  const rowTapped = methodBody(panel, '- (void)rowTapped:(UIButton *)sender');
  assert.match(rowTapped, /if \(row == 1\) \{ \[self cancelPendingConfirmation\]; \[self showPage:RBSettingsApplications\]; return; \}/);
  assert.match(rowTapped, /if \(row == 2\) \{ \[self showPage:RBSettingsApplications\]; \[self savePendingApplication\]; return; \}/);
  const controller = source('Reborn/RBController.m');
  assert.doesNotMatch(controller, /brushHandler|clearHandler|绘图设置|绘画设置/);
  assert.match(controller, /label:@"设置" action:@selector\(settingsTapped:\)/);
  assert.match(controller, /_screenshot\s*=\s*\[self barButton:@"camera" label:@"保存系统截图" action:@selector\(screenshotTapped:\)\]/);
  assert.match(controller, /_barButtons = @\[_close, _clear, _brush, _undo, _screenshot, _gear\]/);
  assert.match(controller, /label:@"画笔设置" action:@selector\(showBrushFromButton:\)/);
  assert.match(controller, /clearTapped:[\s\S]*?\[_drawView clear\]/);
});

test('settings page sizes respond to content, font and host changes', () => {
  const panel = source('Reborn/RBSettingsPanel.m');
  for (const signature of [
    '- (void)showPage:(RBSettingsPage)page',
    '- (void)searchChanged:(id)sender',
    '- (void)contentSizeChanged:(NSNotification *)note',
  ]) assert.match(methodBody(panel, signature), /\[self reloadContent\]/);
  const available = methodBody(panel, '- (void)updateAvailableSize:(CGSize)size');
  assert.match(available, /_availableSize = size/);
  assert.match(available, /\[self updatePreferredSize\]/);
  const preferred = methodBody(panel, '- (void)updatePreferredSize');
  assert.match(preferred, /\[self measureContentTarget\]/);
  assert.match(preferred, /RBSettingsPanelSizeForContent/);
  assert.match(preferred, /!CGSizeEqualToSize\(preferred, self\.preferredContentSize\)/);
  const controller = source('Reborn/RBController.m');
  assert.match(methodBody(controller, '- (void)preferredContentSizeDidChangeForChildContentContainer:'),
    /container == _settingsPanel\) \[self\.view setNeedsLayout\]/);
  assert.match(methodBody(controller, '- (void)keyboardChanged:'), /\[self layoutSettingsPanel\]/);
});

test('search keeps its dimensions while typing and restores content sizing on exit', () => {
  const panel = source('Reborn/RBSettingsPanel.m');
  const begin = methodBody(panel, '- (void)textFieldDidBeginEditing:');
  assert.match(begin, /_frozenSearchTarget = _contentTarget/);
  assert.match(begin, /_searchEditing = YES/);
  const end = methodBody(panel, '- (void)textFieldDidEndEditing:');
  assert.match(end, /_searchEditing = NO/);
  assert.match(end, /\[self reloadContent\]/);
  const showPage = methodBody(panel, '- (void)showPage:(RBSettingsPage)page');
  assert.match(showPage, /page != RBSettingsApplications[\s\S]*?_searchEditing = NO[\s\S]*?\[_search resignFirstResponder\]/);
  assert.match(methodBody(panel, '- (void)updatePreferredSize'), /RBSettingsPanelTargetWhileEditing/);
});
