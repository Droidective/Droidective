# Overnight run — working state

Scratch file for a long autonomous session, so a context compaction does not
lose the thread. **Delete this when the run is reviewed.** Anything here that
turns out to be durable belongs in `docs/desktop-parity.md` instead.

## Standing instruction

Work the `docs/desktop-parity.md` backlog in order, matching the macOS UI
exactly (the rule is at the top of that file and in `CLAUDE.md`). Commit and
push after each feature so nothing is only local. Report honestly in the
morning — including what was *not* done.

## Where things stand

**Branch:** `feat/desktop-performance` holds everything unmerged, stacked on
`feat/desktop-file-explorer` (PR #263).

| | |
| --- | --- |
| PR #263 | file explorer, 4 commits, head `d6385f7`, UI matched to the Mac |
| stacked | crash catcher, the parity pass, performance monitor, the UI inventory, the handoff prompt |

**GitHub Actions was in a `major_outage` all session.** Nothing could merge; a
tag could not release. Check `githubstatus.com` before diagnosing CI. When it
returns: merge #263, then split the crash and performance commits onto branches
off the new main.

## The Linux build

`scripts/build-desktop-linux.sh` builds the app in a container (Tauri does not
cross-compile). `scripts/smoke-desktop-linux.sh` installs the resulting `.deb`
in a bare `ubuntu:24.04` and runs it under Xvfb.

Learned the hard way:

- the default container gets **1 GB** and Swift's BoringSSL build silently
  stalls there — the script asks for 10 GB, like `make test-linux` does
- AppImage bundling needs `xdg-utils`; without it the whole build fails
  *after* the `.deb` was already written, so the copy step now runs regardless
- `desktop/.linux-cache/` keeps the cargo registry, the target dir and the apt
  archives between runs; both are gitignored

**Decided with the user:** the Linux beta ships **x86_64 only** (arm64 is what
builds natively here, but almost no Linux desktop runs it), under a **non-`v`
tag** (`desktop-linux-preview.1`) so the CI release workflow — which keys on
`refs/tags/v*` and expects a Mac DMG plus the whole beta artifact set — does
not fire and fail.

Order: arm64 build → smoke test (proves the recipe) → x86_64 build under
`--arch amd64 --rosetta` → smoke test → `gh release create --prerelease`.

## Feature order for the night

From the backlog, in order, cheapest-shape-first within each group:

1. **#7 the notification surfaces** — `ToastOverlay`, `NotificationPanelView`
   (the bell in the device bar), `CommandLogView`. Do these before more
   screens: every ported pane currently reports into an inline banner it
   should not have, so each one built first is one more to convert.
2. **#10 device state** — `dev-settings`, `root-status`, `system-restrictions`.
   Toggle tables over one route each; `root-status` already has its route
   (`/v1/device/root`).
3. **#11 connection** — `wifi`, `private-dns`, `network-speed`.
4. **#12 per-app** — `app-info`, `permissions`, `meminfo`, `sandbox-browser`,
   `manage-app`. All hang off the bundle already chosen in Apps.
5. **#13** emulators, install-app. **#14** deep links, bug report.

Each is the same four layers; `lib/deviceinfo.ts` + `/v1/device/props` is the
worked example, and the file explorer is the one for a screen that writes.
**Five** `DaemonBackend` test stubs have to conform when a method is added.

## Log

- Linux build recipe written and proven to compile; AppImage step fixed.
- (append as things land)
