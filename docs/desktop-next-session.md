# Next session — the prompt

Copy the block below into a fresh session. It is kept in the repo rather than
in a chat scrollback so the next run starts from the same place this one ended.

---

```
Droidective — Windows/Linux app (phase 3). Continue bringing it to macOS parity.

START FROM LATEST MAIN — always, before anything else
  cd /Users/rohindh/Project/Personal/Droidective
  git fetch origin --prune
  git checkout main && git merge --ff-only origin/main
  git checkout -b <new-branch>
No stacked PRs. One coherent chunk per PR.

  Rust is installed but NOT on PATH: export PATH="$HOME/.cargo/bin:$PATH"
  Node: source "$HOME/.nvm/nvm.sh" && nvm use 22 (system node is too old for Vite 8)

STATE
  Landed before this session: grouped sidebar + feature tabs, per-feature
  icons, split panes, command palette + pinned, logcat rework, device info.
  Landed in the last session (check whether the PRs merged before assuming):
    - File explorer (#263) — four /v1/files/* routes + /v1/device/root
    - Crash catcher — /v1/crashes/{list,clear}
    - Performance monitor — a `performance` stream topic, record-first
    - A UI-parity pass and a full inventory of the Mac's chrome
  Branch `feat/desktop-performance` holds all of it if any is still unmerged.

READ FIRST
  docs/desktop-parity.md — THE TRACKER. Read the "Status today" preamble and
    the Backlog, in that order. The backlog is numbered and ordered; work it
    in order unless something has obviously changed.
  desktop/README.md — architecture and conventions.

THE RULE THAT MATTERS MOST
  The desktop UI *is* the Mac's UI. The Mac app is the proven one, and the
  point of the port is that someone moving between the two does not have to
  relearn anything. Before building any control, open the macOS view that
  already has it (the tracker names the file) and match its wording, icon,
  confirmation shape and gesture. A double-click stays a double-click; a
  confirmationDialog stays a dialog and does not become a button that arms
  itself. If an idea is genuinely better, it goes into the Mac app FIRST.
  Two standing exceptions, and only these: a keyboard shortcut whose modifier
  has no Windows/Linux equivalent, and a label that names a platform.

THE TASK
  Work the backlog in order. Next up is #7: the notification surfaces.
    - ToastOverlay — the transient, top-trailing action result, with a level
      and an optional Show in folder.
    - NotificationPanelView — the persistent history column behind the bell in
      the device bar. A different thing from a toast; the Mac has both.
    - CommandLogView — every CommandLog.userInitiated adb call.
  Do these before more Settings or more screens: every ported screen currently
  reports into an inline banner it should not have, so each one built first is
  one more to convert. Converting the four existing panes (Apps, File
  Explorer, Crash Catcher, Performance) to toasts is part of the same chunk.

  The daemon has no notion of a "user-initiated" call yet. CommandLog is an
  ADBKit actor gated on a task-local; the daemon will need to wrap its route
  handlers in CommandLog.userInitiated and expose the log over a route.

  Every remaining screen needs FOUR layers — `lib/deviceinfo.ts` +
  /v1/device/props is the worked example on main, and the file explorer is the
  worked example for a screen that WRITES:
    1. daemon: a DaemonProtocol.Route case + wire shapes, a DaemonBackend
       method (ALL FIVE test stubs must conform), a DaemonServer case, tests
    2. Rust: a wire type in daemon/wire.rs, a client method, a
       #[tauri::command], registered in lib.rs
    3. TS: a lib/*.ts holding the *decisions* (tested), a hook, then a thin
       pane that only renders
    4. route the pane in FeaturePane.tsx (via components/panes.ts)

HARD CONSTRAINTS
  macOS app must not change. It never talks to the daemon (decided).
  Portability edits gate with #if canImport(Darwin) — gate, don't replace.
  Every change ships with tests; zero warnings (oxlint's max-lines and
  max-lines-per-function are errors here in practice — split early).
  Device-shell values go through shellQuote in ADBKit, never in the client.
  Never guess a dependency version or action SHA — look it up.
  main requires an approving review; merge with
  `gh pr merge --merge --admin --delete-branch` once CI is green.
  Merge ONE PR at a time and verify the trunk moved before the next.

VERIFY
  make desktop-test          # tsc + oxlint + vitest + cargo fmt/clippy/test
  cd droidectived && swift test -Xswiftc -warnings-as-errors
  make verify                # ADBKit + ReactotronMCP + droidectived + AppTests

  Run it for real (rebuild the sidecar after ANY daemon change):
    export PATH="$HOME/.cargo/bin:$PATH"
    ./scripts/build-daemon-sidecar.sh debug
    cd desktop && npx tauri build --debug --no-bundle
    cp src-tauri/binaries/droidectived-* src-tauri/target/debug/droidectived
    pkill -f droidective-desktop; ./src-tauri/target/debug/droidective-desktop &
  emulator-5554 is usually running. Screenshot the WINDOW ONLY
  (screencapture -R with bounds from System Events), never the full screen.

GOTCHAS (the ones that cost time last session)
  GitHub Actions was in a major outage for a whole session — runs were created
    and every job cancelled. Check githubstatus.com before diagnosing CI.
  cargo fmt is a SEPARATE gate from clippy. Run `make desktop-test`.
  build-daemon-sidecar.sh exits early with "rustc is not on PATH" — and the
    stale sidecar is then SILENT. Export PATH before running it.
  A pre-commit hook blocks any command matching `git push.*main`, including
    `gh pr create --base main`. Split the push and the PR create.
  Driving the UI: the webview's AX tree is NOT reachable via AppleScript's
    `entire contents of window 1` (it returns 0). Use the raw AX API through
    pyobjc — `uv run --with pyobjc-framework-ApplicationServices` — walking
    AXChildren from AXUIElementCreateApplication. AXPress works on buttons,
    checkboxes and menu items. A <select> needs AXPress to open its native
    menu, then AXPress the AXMenuItem; setting its AXValue silently does
    nothing. A React text field usually ignores an AX value write, so give
    every field an aria-label and expect typing to need a hand.
  No synthetic keystrokes — a global key code fired a macOS Log Out prompt.
  An armed confirmation expires in 5 s, so two AXPresses across two shell
    commands will miss it; press both from one process.
  Restored tabs mean the pane you want may not be the active one — press the
    tab button before looking for its controls in the AX tree.
  Synthetic mouse events never start an HTML5 drag in WKWebView, so drag paths
    cannot be automated — ask the user to test drags by hand. Keep the
    *decision* a drop makes in lib/ where it can be unit-tested.
```
