---
name: debug-app
description: Debug a misbehaving Droidective build — where state and logs live, known failure signatures (Sparkle-replaced dev builds, leaked mirror sessions, corrupt stores), and how to reproduce in a test first.
---

# Debugging Droidective

## Reproduce in ADBKit first

Most bugs live below the UI. Feed the failing input (captured adb output, a
real wire frame) to the pure parser or service through `MockProcessRunner`
and turn the repro into a failing test — that's the fix's regression guard.
Only debug at the UI when the logic layer checks out.

## Where state lives

- Stores: `~/Library/Application Support/Droidective/` — one JSON per
  `JSONStore` (bundles, deep links, custom commands, layout, presets,
  overrides, prefs). A corrupt file is set aside as `*.corrupt`, not
  deleted — inspect it to see what broke.
- Managed tools: `Application Support/Droidective/tools/` (jadx, apktool,
  frida, Temurin JRE, the seeded jars).
- What adb did: Settings ▸ Command Log shows every user-initiated call —
  if an action's commands are missing there, its code path lacks
  `CommandLog.userInitiated {}` (that's a bug too).

## Live logs and processes

```bash
log stream --predicate 'process == "Droidective"' --style compact
pgrep -fl 'adb|scrcpy|emulator'      # orphaned children after a crash/kill
```

Device side: the app's own Logcat feature, or `adb logcat` scoped to the
target app. `DeviceMonitor` polls every 2s — device-list weirdness within
that window is expected.

## Known failure signatures

- **Dev build behaves like an old release / EPERM re-copy build failures /
  days-old binary mtimes / no `Droidective.debug.dylib` in `MacOS/`** →
  Sparkle silently replaced the Debug bundle at its own path on quit. Guard
  is `SparkleUpdater.updaterAllowed` (never starts in Debug) — if these
  symptoms appear, that guard regressed. Delete the bundle and rebuild.
  Debug string-probes go against the `.debug.dylib`, never the stub
  executable.
- **Runaway CPU** → leaked mirror sessions: a detached mirror view model
  restarting itself. Check for multiple scrcpy-server children.
- **UI freeze / starved async pool** → something blocked a cooperative
  thread; `SystemProcessRunner` must use handlers, never `waitUntilExit`
  (the 16-process canary test guards this).
- **A parser "randomly" missing lines** → CRLF input split on `"\n"`.
  `"\r\n"` is one Character; use `.newlines`.
- **A pane's tab drops dead while some feature tab is open** → a
  feature-wide `.onDrop` intercepting by geometry; drags also die silently
  when a UTI isn't declared in `UTExportedTypeDeclarations`.
- **View doesn't reload after a device authorizes** → `.task(id:)` keyed on
  serial only; the key must include readiness (`targetSerials.first`).

## Debug-build gotchas

- Quit the app before `defaults write` against its domain — it rewrites
  prefs on exit over yours.
- `make build` can skip relinking — check the binary timestamp before
  concluding "my change did nothing".
- Native notifications may be silently denied for ad-hoc-signed debug
  builds; verify notification behavior on release builds only.

## Verifying the fix live

Use the `verify` skill — windowed screenshots and AX driving without
stealing the user's screen.
