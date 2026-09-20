# Next session — the prompt

Copy the block below into a fresh session. It is kept in the repo rather than
in a chat scrollback so the next run starts from the same place this one ended.

---

```
Droidective — Windows/Linux app (phase 3). Continue bringing it to macOS parity.

START FROM LATEST MAIN — always, before anything else
  cd /Users/rohindhr/Projects/Droidective
  git fetch origin --prune
  git checkout main && git merge --ff-only origin/main
  git checkout -b <new-branch>
One coherent chunk per PR. Stack only if you cannot merge; say so in the body.

  Rust is installed but NOT on PATH: export PATH="$HOME/.cargo/bin:$PATH"
  Node: source "$HOME/.nvm/nvm.sh" && nvm use 22 (system node is too old for Vite)

STATE
  The shell is done. 30 of the 32 full-screen views have a pane; the two
  without are `frida-console` (needs a rooted device) and `ios-logs` (out of
  scope — a macOS toolchain). That number was wrong in two places at once for
  a while, so recompute rather than trust it: catalogFeatureIDs filtered to
  view/system, against the desktop pane router.

  Landed most recently (check the PRs merged before assuming):
    - The Command Log, the screenshot editor, the video editor, Send Text
      snippets and the pull progress strip (#356-#360)
    - The Mac gained the port's richer pull strip: cancel, a byte count, and a
      partial file cleaned up (#361). The port is the one that had it first.
    - The parity tracker became trustworthy (#362): the generator no longer
      emits Swift string interpolations as unmatchable items, and it now
      PRESERVES TICKS across a regenerate — before that, auditing was erased by
      the next `generate-parity-tracker.py` run.
    - Reactotron: the reverse-tunnel button moved into the toolbar, where it is
      reachable while a client is connected (#363); the daemon relay learned to
      SEND to a client (#364); and the State screen landed (#365).

  THE AUDIT IS THE CURRENT MODE OF WORK. `docs/desktop-parity.md`'s per-feature
  checklists are it. A tick means the affordance was found in desktop/src *and
  read in place*. Two passes are done — the Connection group, and Reactotron.
  Each found real defects, not just wording; see "The audit, and what it has
  covered" in the tracker for what is left and how big each piece is.

READ FIRST
  docs/desktop-parity.md — THE TRACKER. Read "Status today" and then the
    Backlog. Work it in order unless something has obviously changed.
  desktop/README.md — architecture and conventions.
  docs/droidectived-protocol.md §4–5 — the route and topic tables.

THE RULE THAT MATTERS MOST
  The desktop UI *is* the Mac's UI. Before building any control, open the macOS
  view that already has it (the tracker names the file) and match its wording,
  icon, confirmation shape and gesture. A double-click stays a double-click; a
  confirmationDialog stays a dialog and does not become a button that arms
  itself. If an idea is genuinely better, it goes into the Mac app FIRST.
  Two standing exceptions: a keyboard shortcut whose modifier has no
  Windows/Linux equivalent, and a label that names a platform.

WHAT IS LEFT, roughly in the tracker's order
  - Reactotron's REPL and custom Commands panes — the last two of its four
    views. Both send a command and read the answer off the timeline, exactly as
    State does, so `useReactotronState` + `lib/reactotron-state.ts` is the
    worked example and `/v1/reactotron/send` already exists. REPL is the
    smaller: `repl.ls` lists what is in scope, `repl.command` evaluates.
  - The welcome tour (backlog 22). The Mac's demo stage plays recordings of the
    *Mac* app, which would be the wrong chrome here, so the six drawn fallbacks
    are what to follow.
  - What's New, and the recurring capped star prompt.
  - Settings ▸ MCP — a port task of its own size: `ReactotronMCP` is
    `#if canImport(Network)`-gated end to end and taps ADBKit's Apple-only
    `ReactotronServer`, so serving it off Apple means feeding `McpCommandStore`
    from the daemon's NIO relay instead.
  - The updater (23) — blocked on a signing keypair, which is the maintainer's
    to create.
  - The QR-code tab of the wireless sheet. `QrPairing` is already portable in
    ADBKit; it needs a daemon verb (a minutes-long stream of phases, not one
    request) and a QR renderer. **It cannot be verified on an emulator** — adb
    37 dropped Bonjour and openscreen ignores same-host advertisements, so the
    last leg needs a physical phone.
  - `frida-console`, which needs a rooted device.
  - The installed-apps picker and bundle manager; the overrides pill; the
    install inbox; the self-metrics overlay.
  - Inside screens: the File Explorer's keyboard navigation and clipboard keys,
    Install App's live stage line, Memory Usage pausing when its tab is hidden.

EVERY FEATURE IS FOUR LAYERS
  1. daemon: a `DaemonProtocol.Route` case (or a `StreamProtocol.Topic`), wire
     shapes, a `DaemonBackend` method — add the default to
     `Tests/DaemonCoreTests/BackendDefaults.swift`, not to five stubs — a
     `DaemonServer` case, and tests
  2. Rust: a wire type in daemon/wire.rs, a client method, a
     #[tauri::command], registered in lib.rs
  3. TS: a lib/*.ts holding the *decisions* (tested), a hook, a thin pane
  4. route the pane in FeaturePane.tsx (via components/panes.ts)

VERIFY
  make desktop-test          # tsc + oxlint + vitest + cargo fmt/clippy/test
  cd droidectived && swift test
  cd ADBKit && swift test

  Run it for real (rebuild the sidecar after ANY daemon change):
    export PATH="$HOME/.cargo/bin:$PATH"
    ./scripts/build-daemon-sidecar.sh debug
    cd desktop && npx tauri build --debug --no-bundle
    cp src-tauri/binaries/droidectived-* src-tauri/target/debug/droidectived
    pkill -f droidective-desktop; ./src-tauri/target/debug/droidective-desktop &

GOTCHAS (the ones that cost time)
  An unstructured `Task { }` does NOT inherit its parent's cancellation. A pull
    started inside one survived the unsubscribe meant to stop it, and every
    unit test passed — the 600 MB transfer went on copying after the strip had
    gone. Await cancellable work in the subscription's own task.
  The emulator's own `screenrecord` produces one-frame files with no duration.
    For a real device clip, use the app's recorder (/v1/record/start + stop).
  oxlint's max-lines (300), max-lines-per-function (100) and max-dependencies
    (10) are errors here in practice. Split early; the repo's own pattern is a
    `*Parts.tsx` sibling or a purpose-named `lib/` module re-exported from its
    barrel.
  cargo fmt is a SEPARATE gate from clippy. Run `make desktop-test`.
  build-daemon-sidecar.sh exits early with "rustc is not on PATH" — and the
    stale sidecar is then SILENT. Export PATH before running it.
  A pre-commit hook blocks any command matching `git push.*main`, including
    `gh pr create --base main`. Split the push and the PR create.

DRIVING THE UI — read this before planning to screenshot anything
  DO NOT BUDGET ON IT. Synthetic clicks into the webview work for a while and
  then stop landing — they still move the cursor and still trigger hover, but
  the click does nothing. This has now degraded mid-session three sessions
  running, and each time the recovery attempts cost more than the screenshot
  was worth. Native panels, the Mac app and the menu bar are unaffected.
  Screen Recording permission may also not be granted to the terminal:
  `screencapture` then returns a *black* image rather than failing. A black
  capture WITH permission granted usually means the window is on another Space
  — check CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly) and
  relaunch it onto the active one rather than chasing the permission.
  Keystrokes never reach the page. They do reach a native open/save panel:
  Shift-Cmd-G, a full path, Return twice — but in a SAVE panel type a bare
  filename, since a leading slash opens go-to-folder and the name becomes ".".
  What works instead, and is better anyway:
    - component tests (@testing-library/react is already a dependency, and
      `NetspeedPane.test.tsx` is the worked example) for anything on screen
    - curl against the running app's own daemon for routes: read the port with
      `lsof -nP -iTCP -sTCP:LISTEN -a -p $(pgrep -f 'droidectived --port')` and
      the token from
      "$HOME/Library/Application Support/com.rohindh.droidective.desktop/droidectived.token"
    - a `websockets` client for stream topics — and for Reactotron, a fake
      client that *answers*. `state.values.request` -> `state.values.response`
      is a dozen lines of python and proves the whole round trip; that is how
      the State screen was verified without ever rendering it.
  Synthetic mouse events never start an HTML5 drag in WKWebView, so every drag
  path is checked by hand — keep the *decision* a drop makes in lib/.
```
