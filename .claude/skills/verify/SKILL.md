---
name: verify
description: Build, launch, and drive Droidective to verify a change at the real UI. Covers the AX-automation recipe (windowed screenshots, menu/button driving) and its gotchas.
---

# Verifying Droidective changes live

## Build & launch

```bash
make build          # xcodegen + xcodebuild; zero warnings required
pkill -x Droidective; open DerivedData/Build/Products/Debug/Droidective.app
```

## Screenshot without stealing the user's screen

The user usually works on the Mac alongside you — full-screen `screencapture -x`
grabs *their* frontmost app. Capture the app window by ID instead:

```bash
WID=$(swift -e 'import CoreGraphics; let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]; for w in l { if (w["kCGWindowOwnerName"] as? String) == "Droidective", (w["kCGWindowLayer"] as? Int) == 0 { print(w["kCGWindowNumber"] as! Int) } }' | head -1)
screencapture -x -o -l "$WID" out.png
```

Window IDs go stale after windows close/reopen — refetch on "could not create
image from window".

## Driving the UI (System Events AX)

- The main window is `window "<current feature title>"` (title follows the open
  feature — list `name of every window` first). Content lives under `group 1`.
- SwiftUI `Menu` pills: `click devMenu` then `delay 0.8` then
  `click menu item "…" of menu 1 of devMenu` in ONE osascript run. Split runs
  leave the menu stuck open and later clicks land wrong.
- Sheets: `sheet 1 of window …`, content under `group 1`. SwiftUI buttons here
  often have NO AX title — address by index; check candidates with
  `enabled of button N` first.
- `perform action "AXPress"` works on buttons and works in the background (no
  frontmost needed).
- **AX `set value` on a SwiftUI TextField updates the display but NOT the
  binding** — buttons gated on that state stay disabled and presses no-op.
  `AXConfirm` doesn't help. Real keystrokes are the only way, which needs
  focus the user may be using; prefer flows that need no typing, or ask the
  user to type/test that step.
- Read ground truth over guessing from pixels: `value of text field 1`,
  `enabled of button 1`.
- To prove a button action actually ran, watch for the spawned process:
  `pgrep -fl "adb connect"` in a background loop around the press.

## Handy real-device stand-ins

- A running emulator counts as a non-wireless ready Android device.
- `adb connect 127.0.0.1:9` → instant "failed to connect … Connection refused"
  (exit 0!) — good error-path input.
- After `adb tcpip 5555` on an emulator it re-registers by itself;
  `adb connect 127.0.0.1:5555` adds a second (wireless) transport —
  `adb disconnect 127.0.0.1:5555` cleans up.
