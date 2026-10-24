# iPad Pro 2018 / iPadOS 15.1 regression checks

Run after installing the new package and respringing, so the old dylib is unloaded.

1. Open Settings -> 全局画板. Confirm the master, home-screen, and volume-shortcut
   switches are on; the floating-ball switch is off; all app switches are off.
   Enable one app and leave another disabled. Enter Split View. No floating ball
   should appear by default.
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
   without respringing. Toggle ball visibility independently; finally turn the
   master switch off and verify all plugin entry points stop responding.

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
