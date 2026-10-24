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
10. Verify an enabled third-party app logs `initialized` with `backend=Cephei`
    and `enabled=1`, then `ball.shown`. A legacy-lifecycle app may report
    `scenes=0` and `scene=legacy`; it must still show a tappable ball. After an
    unlocked volume combo, verify its `toggle.received` has `allowed=1` and
    `present.shown` follows. A background/disabled app must log `allowed=0`.
11. Change app switches and drawing preferences across Settings, SpringBoard,
    and a third-party app. Confirm changes arrive after cache refresh without a
    respring, survive reopening, and preserve old enable choices and pen values.
    If the app has no `loaded` entry, inspect injector/dyld logs; if it loads but
    logs `enabled=0`, inspect shared configuration; if it is enabled but logs
    `ball.skipped`, inspect the recorded foreground/scene reason.

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
