# Dr4w Reborn

A **source-level** reimplementation of Dr4w's "draw anywhere" overlay, built on the
same open-source drawing engine Dr4w bundles
([ACEDrawingView](https://github.com/acerbetti/ACEDrawingView)).

Unlike the earlier helper-tweak approach (hooking a closed-source binary), every
pixel here comes from code in this repo, so the UI can be changed freely.

## What is inside

```
Engine/                 vendored ACEDrawingView (MIT, see NOTICE)
  ACEDrawingView.m/h        canvas, tool stack, undo/redo, snapshot
  ACEDrawingTools.m/h       10 tools: pen, line, arrow, rect, ellipse,
                            eraser, draggable text, triangle, pentagon, hexagon
  ACEDrawingLabelView.m/h   draggable / rotatable text label
  ACEDrawingToolState.m/h   undo state

Reborn/
  RBManager.m/h          singleton, overlay window, volume U->D trigger
  RBWindow.m/h           UIWindow subclass (per-project window behaviour)
  RBController.m/h       canvas + toolbar + settings
  RBPrefs.m/h            tool / color / width persistence

Preferences/           system Settings page and installed-app switches
Shared/                settings storage and tested activation/shortcut policy
Dr4wReborn.plist        inject into SpringBoard and UIKit apps
control                 deb metadata
.github/workflows/      builds the deb on every push
```

## Features (first milestone)

- Transparent full-screen canvas over SpringBoard
- 10 drawing tools (pen, line, arrow, rectangle, ellipse, eraser, text,
  triangle, pentagon, hexagon and their filled variants)
- Undo, clear canvas
- Tool / colour / width picker inside the panel (no Preference bundle needed)
- Screenshot: flattens the drawing onto white and saves a PNG to
  `/var/mobile/Media/Dr4wReborn/`
- Summon / dismiss with **Volume Up -> Volume Down** (within 0.9 s, device unlocked)
- Settings -> 全局画板: master switch, home-screen switch, volume shortcut,
  and an App 启用 list with native app icons and hidden-component filtering
- Apps default to disabled. Enabling an app shows its floating ball on entering
  that app; tap it to draw. Old permanent ball-hiding preferences are ignored.
- Long-press the ball (or use the drawing menu) to hide it for the current visit.
  Returning to the app restores it. Settings changes apply without respringing.
- Locking closes the drawing panel; SpringBoard observes volume button methods
  instead of polling audio or frontmost-app interfaces. Normal volume behavior is preserved.
- Preferences persist between launches
- Shared preferences use Cephei 2.0 (`HBPreferences`) so sandboxed App Store apps
  read the same enable list and drawing settings as Settings and SpringBoard.

## Install

1. Actions tab -> `build` -> Run workflow (or just push).
2. Download the `Dr4wReborn-deb` artifact and install with Sileo/Filza.
3. Respring.
4. Open Settings -> 全局画板 -> App 启用 and enable the apps you want.
5. In an enabled app (or on the home screen), press Volume Up then Volume Down
   within 0.9 seconds to toggle the panel. The volume shortcut has its own switch.
6. Return to an enabled app and tap its floating ball to open the panel.
   Long-press temporarily hides it; leaving and re-entering the app restores it.

After upgrading, respring before testing so SpringBoard unloads the old dylib.
This rootless package also requires **Cephei Tweak Support 2.0 or later**
(`ws.hbang.common`), available from [Chariz](https://chariz.com/get/cephei).
Install through Sileo so dependencies are resolved, then fully close and reopen
the enabled third-party apps. Existing settings are kept in the same preference domain.
Device stability checks are listed in [tests/IPAD-SMOKE-TEST.md](tests/IPAD-SMOKE-TEST.md).

Diagnostic system-log entries start with `[Dr4wReborn <version>]`. They record
`loaded`, `initialized` (enabled state, scene count),
`toggle.received`, and `ball.shown`/`ball.skipped`. They do not include drawing
content. A process without `UIScene` uses its legacy application window instead.

If Cephei's sandbox IPC is unavailable, apps fetch a cached configuration snapshot
from this tweak's SpringBoard service (`cy:` / `lh:`). Requests run off the main
thread with bounded send/receive timeouts. Only this tweak's domain is exposed,
and remote writes are limited to numeric drawing preferences. Transport failures
retain the last successful snapshot; a successfully empty enabled-app list still
disables all apps. Logs `settings.service`, `settings.transport`, and
`settings.snapshot` distinguish registration, connection, and refresh failures.

The vertical toolbar moves with a one-finger drag anywhere on the bar, including its buttons, and stays inside the current app's
safe area. Each app retains its own relative position across closing, app restarts,
respring, rotation and Split View resizing. Apps without a saved position start
at the right-hand center. Its scrollable actions run from Close through Clear,
Pencil, Undo and Settings; use two fingers to scroll the actions in short windows.
Dragging cancels button taps. VoiceOver users can move the bar through the Settings
button's four directional custom actions. Settings includes a live 60–150% global
toolbar-size slider; compact sizes preserve 44-point button targets.

The Settings menu and its tool, ball, size and App pages use the same translucent
rounded material as the brush panel. App management is searchable by name or bundle
identifier both here and in system Settings. Changes merge one App at a time through
SpringBoard and report save failures. Disabling the current drawing App requires
confirmation because it closes the canvas and floating ball. App directory loading
runs off the SpringBoard main thread, and the search panel avoids the keyboard.

The Pencil button opens a 60 pt wide vertical panel with four icon-only color
slots and a numbered vertical 1–30 pt slider with a live line preview. Up means
thicker. Tap a color to use it; tap the selected slot again to edit it in the
system picker. Edits preview immediately and save on picker dismissal, replacing
that slot for all apps. There is no More Colors button. Selections leave the
panel open; tap the centered close icon or outside to close. The panel shares
the toolbar's translucent material and accessibility fallbacks in the same view
hierarchy, without a system popover shell. The system picker returns to this panel.
Split View keeps the panel inside the safe area and the system picker as a bounded
popover rather than a large sheet. Width changes apply immediately; persistence occurs
on release or dismissal. Legacy five-step width choices are retained until a new
width is selected. Toolbar positions are merged by SpringBoard per app only at
gesture end; generic bridge writes cannot replace the position dictionary.
Plugin controls use semantic black/gray colors (white/gray in
dark appearance), while drawing colors and installed-app icons retain their colors.

## Where to change things

| Want to change | File |
|---|---|
| Toolbar position / size / buttons | `Reborn/RBController.m` -> `-buildBar` |
| Which tools appear in the menu | `Reborn/RBController.m` -> `-showTools`, `RBPrefs.h/m` |
| Colours and widths | `Reborn/RBPrefs.m` (`colors`, `widths`) |
| Trigger (keys, timing) | `Reborn/RBManager.m` -> `RBHandleVolume` |
| Window level / touch behaviour | `Reborn/RBWindow.m`, `RBManager.m` -> `present` |
| Default tool / colour | `Reborn/RBPrefs.m` |

Everything is ordinary Objective-C; rebuild after each edit.

## Known MVP limitations

- The screenshot saves the **drawing on a white background**, not a capture of the
  SpringBoard content behind it (capturing the screen needs a private snapshot API;
  can be added later).
- The Settings page requires PreferenceLoader, installed as a package dependency.
- Text tool uses the system keyboard (the window is made key while open).

## License / attribution

`Engine/` is [ACEDrawingView](https://github.com/acerbetti/ACEDrawingView) by
Stefano Acerbetti, MIT licensed — see `NOTICE`.
The rest of the code is yours to modify.
