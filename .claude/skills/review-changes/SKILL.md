---
name: review-changes
description: Review a Droidective diff (working tree, branch, or PR) with the project's review order and its known red flags — ADBKit/App boundary, shellQuote, CRLF splitting, task readiness, CommandLog, translucency tokens.
---

# Reviewing Droidective changes

Sync first (`git fetch origin`), then review the diff in this order. Stop at
the first tier with real findings before polishing lower tiers.

## 1. Architecture

- Logic stays in ADBKit, UI in App. Any `Process`, `adb`, or parsing inside a
  SwiftUI view is a finding — it belongs in an ADBKit service with a pure
  static parser.
- No new Apple-only framework imports in ADBKit (Network, CoreMedia,
  AVFoundation, VideoToolbox, CryptoKit, os, Darwin) outside the already
  Apple-bound subsystems; a genuinely needed one goes in its own small file.
  No new `/usr/bin/...` or `/bin/zsh` literals, no corelibs-Foundation traps
  (`NSDataDetector`, `FileHandle.bytes`, `FileManager.replaceItemAt`,
  `OSAllocatedUnfairLock`, raw `posix_spawn`, `readabilityHandler` as EOF).
- Existing seams (`ProcessRunning`, injected directories) intact.

## 2. Correctness — the project's recurring bugs

- **Every user-controlled value reaching `adb shell` is `shellQuote()`d.**
  Path, URL, SSID, hostname, proxy, locale, free text — no exceptions.
  Caller-side validation is UX, not the security boundary. `push`/`pull`/
  `exec-out` are sync-protocol (no shell, no quoting).
- Output split with `.components(separatedBy: .newlines)`, never `"\n"` —
  `"\r\n"` is ONE Swift Character and CRLF input silently breaks.
- `.task(id:)` keys include device readiness (`targetSerials.first`), not
  just serial; `!Task.isCancelled` guarded before writing fetched results
  into `@State`; long-running adb work in a cancellable `Task`.
- Failure paths handled — non-zero exit, empty output, partial output — not
  optimistic success.
- View features that run adb directly wrap user actions in
  `CommandLog.userInitiated {}` (background polling stays out).
- New UI fills with `.bgRoot`/`.bgSurface` or the translucency modifiers —
  a raw asset Color, `Color.black`, or default `List`/`Form` material blocks
  the window glass and only shows up by eye at <100% opacity.
- Feature-id contract: a new feature followed the CLAUDE.md checklist — the
  silent failure modes (missing `detailByKind` case → "Coming Soon"; missing
  hub absorption; missing `userInitiated`) have no automated guard.
- No feature-wide `.onDrop` (it silently kills tab drops); new drag UTIs
  declared in `UTExportedTypeDeclarations`.

## 3. Tests

- Parser + arg-vector tests present *and meaningful* — would they fail if
  the code broke? User input hitting `adb shell` has a test asserting the
  `shellQuote`d form in `runner.invocations`.
- Edges covered: empty input, CRLF, malformed/partial output, non-zero exit.
- A new cross-feature rule got a registry-invariant loop test (the
  `everyFeature*` pattern), not review folklore.
- Behavior, not implementation: a behavior-preserving refactor must not
  break them.

## 4. Quality

- Dead code deleted in the same change (replace, don't deprecate), files
  stay focused (no new weight on `AppState` or the biggest views), names
  clear, zero warnings (`swift test -Xswiftc -warnings-as-errors`).

## Verify findings before reporting

Adversarially check each finding against the actual code — plausible
findings often misread it (a "dead code" removal can delete a live path).
Report file:line, concrete failure scenario, and a recommended fix.
