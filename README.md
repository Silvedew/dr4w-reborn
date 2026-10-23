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

Dr4wReborn.plist        inject only into SpringBoard
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
- Summon / dismiss with **Volume Up -> Volume Down** (within 0.65 s)
- Preferences persist between launches

## Install

1. Actions tab -> `build` -> Run workflow (or just push).
2. Download the `Dr4wReborn-deb` artifact and install with Sileo/Filza.
3. Respring.
4. Press Volume Up, then Volume Down, to open the panel.

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
- No Preference bundle yet; settings live in the in-panel menu.
- Text tool uses the system keyboard (the window is made key while open).

## License / attribution

`Engine/` is [ACEDrawingView](https://github.com/acerbetti/ACEDrawingView) by
Stefano Acerbetti, MIT licensed — see `NOTICE`.
The rest of the code is yours to modify.
