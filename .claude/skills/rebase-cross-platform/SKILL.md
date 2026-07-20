---
name: rebase-cross-platform
description: Rebase the Windows/Linux port branch (feat/cross-platform-core) onto latest main, resolve the port's known conflict spots, audit main's new ADBKit code for portability traps, then re-verify the gates (macOS suite, make test-linux). Use when asked to rebase/sync the cross-platform branch with main, or after main lands features the port branch needs.
---

# Rebasing feat/cross-platform-core onto main

The port branch carries compile-gates and portable seams on top of main.
Rebasing = replay those onto main's latest, then prove the gates still hold.
Work in the branch's own worktree; never bare `git stash` (the stash stack is
shared across worktrees).

## 1. Sync and rebase

```
git fetch origin
git merge-base HEAD origin/main   # note it — the audit range below
git rebase origin/main
```

## 2. Resolve conflicts with the port's intent in mind

- **CLAUDE.md** — keep the port branch's Architecture note, `make test-linux`
  line, and test counts; fold in main's new Status items.
- **ADBKit/Package.swift** — keep the swift-crypto dependency and its
  platform conditions; fold in anything main added.
- **Gated files** (`Services/Mirror/*`, `ReactotronServer`/`Service`,
  `ScreenRecorder`, the JSConsole/Mirror/Reactotron wire tests) — keep the
  `#if canImport` gates wrapping whatever main changed inside them.
- **Seam files** (`ToolLocator`, `ManagedToolStore`, `SystemProcessRunner`,
  `JSONStore`, `LogcatStream`, `SimulatorLogStream`, `CustomCommandService`,
  `SimctlClient`) — keep both: main's logic inside the port's per-OS
  structure.

## 3. Audit what main landed since the old base

New main code arrives ungated. Sweep the range for the known traps:

```
git log --stat <old-base>..origin/main -- ADBKit
rg -n "^import (Network|CoreMedia|AVFoundation|VideoToolbox|CryptoKit|Darwin|os)$" ADBKit/Sources
```

- A new Apple-only import outside the gated subsystems → gate the file (or
  route through the existing seam; the per-subsystem table is in
  `docs/cross-platform.md`).
- `NSDataDetector`, `FileHandle.bytes`/`.lines`, `FileManager.replaceItemAt`,
  `OSAllocatedUnfairLock`, raw `posix_spawn` → each has a portable pattern
  already (`ConsoleLinkDetector` gate, `FileHandleLines`, `JSONStore.save`,
  `NetworkTrafficMeter`, `EmulatorService.spawnDetached`) — copy it.
- `URLSession` in a new file → add the `#if canImport(FoundationNetworking)`
  import block.
- Hardcoded `/usr/bin/...`, `/bin/zsh` → `HostArchive`,
  `ToolLocator.loginShell(environment:)`, `CustomCommandService.fallbackShell`.
- New tests that stat the real filesystem or assume host facts
  (`/usr/bin/xcrun` exists, zsh is the shell) → use the injectable
  `isExecutableFile` seams (`SimctlClient`, `ToolLocator`,
  `FeatureEngine(simctl:)`) and the platform constants.
- corelibs gotcha to remember: `readabilityHandler` never delivers its empty
  EOF callback when the final data and the writer's close coincide — never
  rely on it for EOF off-Darwin (use `FileHandleLines` / the PipeCollector
  thread pattern).

## 4. Verify the gates, in order

```
cd ADBKit && swift test                                    # macOS, full suite
swift build --build-tests -Xswiftc -warnings-as-errors     # zero warnings
make test-linux           # the port gate (container system start once per boot)
make build                # the App still builds
```

## 5. Push

Only ever this branch's own remote, and only with lease:

```
git push --force-with-lease origin feat/cross-platform-core
```
