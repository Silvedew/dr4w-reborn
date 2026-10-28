# iPad Pro 2018 / iPadOS 15.1 regression checks

Run after installing the new package and respringing, so the old dylib is unloaded.
Confirm Cephei Tweak Support >= 2.0 is installed; fully close and reopen the test apps.
Use one system app and at least two sandboxed third-party apps (for example,
Quark HD and Eudic if installed). Native CI settings tests use a Cephei test double;
they do not establish real App Store sandbox/IPC behavior.

1. Open Settings -> 全局画板. Confirm the master, home-screen, and volume-shortcut
   switches are on; there is no separate floating-ball switch. Existing app
   selections must survive upgrading. In App 启用, enable one app and leave
   another disabled. Enter Split View: only the enabled app should show a ball.
   Tap it to open the drawing panel.
2. On an unlocked device, press Volume Up then Volume Down within 0.9 seconds.
   Verify the drawing panel opens and closes on the home screen and in the
   enabled app, but not in the disabled app. Repeat at minimum and maximum volume.
   Confirm normal volume adjustments still work, including with the shortcut off.
3. Lock while the drawing panel is open. Unlock after 1 minute and again after
   at least 15 minutes; the panel must remain closed and the UI must respond.
4. Repeat lock/unlock 20 times, including locking immediately after opening the
   panel. No delayed window should reappear or steal focus after unlocking.
5. Draw, undo, clear, and switch apps. Confirm the canvas still works.
6. Check SpringBoard crash reports for the same test period. A clean compile and
   source regression guards do not establish device stability.
7. While an app is running, turn its app switch off in Settings, then return.
   It must not respond or show a ball. Re-enable it and verify the shortcut works
   without respringing. Long-press the ball to hide it, change an unrelated setting,
   and verify it stays hidden until leaving and re-entering the app. Finally turn the
   master switch off and verify all plugin entry points stop responding.
8. Verify Settings' 全局画板 entry has the white circular pencil icon. In App 启用,
   each visible app should have its own icon (generic app icon if unavailable).
   Hidden helpers/extensions must not appear. Real apps sharing a name must show
   their distinct identifiers beneath the name and have independent switches.
9. Repeatedly change Split View size, switch scenes, lock/unlock, and return to
   the enabled app. Its ball must be attached to the active scene, remain tappable,
   and not appear in a disabled app. Collect fresh logs if any of these fail.
10. After respring, verify SpringBoard logs `settings.service` with a registered
    `cy:` or `lh:` service. In Bilibili (`tv.danmaku.bilianime`) and a second
    enabled third-party app, verify `settings.snapshot` reports `success=1`
    with `backend=Cephei` or `backend=bridge`, followed by `settings.updated`
    with `enabled=1` and `ball.shown`. Initial `initialized enabled=0` may precede
    the asynchronous snapshot and is not itself a failure. A legacy app may report
    `scenes=0` and `scene=legacy`; it must still show a tappable ball. After an
    unlocked volume combo, verify its `toggle.received` has `allowed=1` and
    `present.shown` follows. A background/disabled app must log `allowed=0`.
11. Change app switches and drawing preferences across Settings, SpringBoard,
    and a third-party app. Confirm changes arrive after cache refresh without a
    respring, survive reopening, and preserve old enable choices and pen values.
    If the app has no `loaded` entry, inspect injector/dyld logs; if it loads but
    logs `enabled=0`, inspect shared configuration; if it is enabled but logs
    `ball.skipped`, inspect the recorded foreground/scene reason.
12. In an app using `backend=bridge`, change pen color/width and ball position,
    reopen it, and verify the changes persist with `settings.write saved=1`.
    If neither service is reachable, save `settings.lookup`/`settings.transport`
    entries alongside the SpringBoard registration entries; do not interpret
    `settings.snapshot success=0` as an intentionally empty enabled-app list.

13. In light and dark appearances, verify the toolbar and monochrome pencil ball remain
    legible over a busy app. Enable Reduce Transparency and Increase Contrast:
    ball and toolbar material become solid and their boundaries remain clear. Enable Reduce
    Motion: button feedback must not scale. Verify VoiceOver announces each action.
14. Drag from the toolbar's background and each of its five buttons using one finger;
    there must be no separate drag handle. Verify buttons do not trigger
    while moving, release keeps the position without snapping, and outside-bar
    gestures continue drawing. Resize Split View and rotate: the toolbar keeps
    its relative position within safe areas and always remains vertical. In short
    windows, use two fingers to scroll to all five controls without moving the toolbar.
    Close and reopen with the volume shortcut, quit/reopen the app, and respring:
    the app's own saved position is restored. Move a second app's toolbar elsewhere and verify the
    positions remain independent. No reset-position menu should appear.
    Verify the Settings button's four directional VoiceOver actions. Confirm ball dragging,
    temporary hiding and idle fade timing still behave as before.
15. Increase text size in Settings, reopen App Enable, and verify duplicate app
    identifiers remain legible, row heights grow, and switches stay operable.
    Search by part of an App name and then by its bundle identifier, including
    mixed case and surrounding spaces. Verify no-results feedback, clear to
    restore the list, and toggle a filtered result without changing any other App.
16. Tap Pencil between Clear and Undo. Verify the 60-point wide
    panel uses a single centered column: four unlabeled color circles, a ring on
    the selected slot, the upright width number, and a close icon. The panel
    should share the toolbar's single translucent material layer, with no arrow.
    Move the toolbar to either side: the panel should open alongside it with
    clearance, rather than covering its buttons. Repeat after rotation/resizing.
    There must be no panel/color title or More Colors button. Tap an unselected
    color to use it, then tap it again to edit. Native-picker changes must preview
    immediately and persist on closing, replacing that slot across apps, app
    restarts and respring. Duplicate slot colors must still select only one slot.
    Narrow Split View must keep the brush panel and native picker inside the app; shrinking
    height scrolls content without widening or turning it into a large sheet. Drag the
    vertical slider up/down from 1 to 30: the upright thumb number, line preview
    and next drawn stroke must match. The parent panel must not scroll during a
    slider gesture; scrolling blank space must still reveal all controls. Close or
    an outside tap closes only the panel without drawing a dot or activating a toolbar button. Close the panel or
    lift the finger; reopening the app must retain the width. Repeat
    with VoiceOver's one-point increments and dismissal. An upgrade must preserve
    existing 2/4/7/12/20 pt choices before using the new slider. Check the Settings
    entry's white circle/gray pencil and toolbar gear; installed-app icons and
    selected ink colors must keep their colors.
    Compare both bars over the same uniform light, dark and colored backgrounds:
    material tint and translucency should match, and all four panel corners must
    stay transparent without white wedges, including while opening/closing and
    rotating. Repeat Reduce Transparency and Increase Contrast; both surfaces
    must use the same solid fallback, while their outer shadows remain intact.
    With VoiceOver, focus stays inside the panel, Escape closes it, and focus
    returns to the triggering button. While changing width or previewing a picker
    color, close drawing through the volume shortcut, lock, or switch apps;
    reopening must retain changes. Closing the native picker must keep the brush
    panel open and operable.

17. With drawing closed and only the floating ball visible, repeatedly rotate
    portrait to landscape, landscape left to right, and reverse midway through
    rotation. Check the entire animation for four black rectangles around the
    ball, not only the final frame. Repeat with the ball centered and near each
    edge, sizes 44/56/80 pt, light/dark appearance and Split View resizing. After
    each rotation, verify tapping, dragging in both axes, edge snapping and saved
    position still work. Repeat in a legacy app without UIScene when available.
    Backgrounding, temporarily hiding, disabling an app or opening drawing must
    not restore a hidden ball when rotation completes. Source guards and layout
    tests cannot establish that UIKit compositing artifacts are gone.

18. Open Settings from the toolbar. Check the main menu, tool selector, ball size,
    opacity, toolbar size and App pages in light/dark mode, Reduce Transparency,
    Increase Contrast and large text. All use the brush panel's rounded material;
    back, close, Escape and outside taps must work without drawing underneath.
    Adjust toolbar size to 60%, 100% and 150%: preview is immediate, targets stay
    at least 44 points, and release/close preserves the size in another App,
    on the home screen and after restarting. Brush panel size stays unchanged.
    The menu title and back/close accessibility labels use “设置”; it has no
    “画笔设置” or “一键清屏” rows. Use the toolbar's Pencil and Clear buttons to
    verify those operations still work. App-disable confirmation remains distinct.
19. In toolbar App management, search names and bundle IDs, scroll, enable a
    different App and check system Settings reflects the change. With the
    keyboard open, rotate and resize Split View: search and results stay inside
    the usable area. Turn off the current App: cancel preserves the drawing;
    confirm closes drawing and the ball. Failed saves and directory loads show
    retry feedback, preserve other Apps, and do not freeze the UI. After searching
    or canceling confirmation, retry must never change the wrong App.

20. Place the ball in the center, at each edge and in every corner. Tap it at
    toolbar scales 60%, 100% and 150%: the top Close button must align with its
    center wherever the full toolbar fits, otherwise remain within the safe area.
    Check rotation, left/right Split View, multiple active scenes and legacy apps.
    Opening must not briefly flash the saved/default toolbar position. Merely
    opening and closing a clamped toolbar must leave the ball unmoved.
21. Move the toolbar by dragging and then by VoiceOver actions. Close once with
    Close and once with the volume shortcut: the ball follows the standard top
    button anchor, bounded inside the host. Repeat after scrolling the toolbar
    in a short window; scrolling alone must not move the return anchor. Tap the
    returned ball and check alignment again. After moving the toolbar, also try
    locking, switching apps and disabling the current App: these automatic
    closures must not update the ball position or restore a hidden/disabled ball.
    Volume opening still restores the saved toolbar position, and the home
    screen continues to work without a floating ball.
    With two scenes of the same App active, deactivate or close the drawing scene:
    its drawing window must close without moving the ball or blocking the other
    scene's ball, and must not restore keyboard focus to the inactive scene.

The supplied crash matches the build-29 (0.1.29) release's arm64e UUID
3554E8B2-0687-32FE-B792-A40E1D2B52B4. In that binary,
__RBBootstrap_block_invoke_5 starts at image offset 0xe7c4. It calls the
frontmost-app function pointer at 0xe800, then the retain stub at 0xe808;
the return address is 0xe80c (59404), matching the crash's +72 frame.
The build-29 source calls RBOtherAppFrontmost from this timer and treats
SBFrontmostApplicationDisplayIdentifier's result as an NSString. The invalid
value 0x10000003 reaches objc_retain. Keep this private query out of the code.

This identifies the binary in this report, not necessarily the device's current
installed version. If the new build fails, collect a fresh timestamped report.
