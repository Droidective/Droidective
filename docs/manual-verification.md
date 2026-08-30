# Manual verification — what a human has to check

A per-release checklist of the things **an agent cannot verify**, so they get
checked deliberately rather than assumed. Walk it before tagging a release.

## The bar for being on this list

Only things that are *impossible* for an agent on this machine — not things
that are slow, awkward, or merely untried. If an agent can drive it against the
emulator, read the result, and tell whether it worked, it does not belong here
and should be automated or driven instead.

That bar matters: a list that collects "would be nice to double-check" stops
being read, and then the genuinely impossible items get missed with it.

**What an agent already does, so you do not have to:** all six test suites; the
Linux suite in a container; **installing the Linux `.deb` in a clean container
and launching, driving and photographing the app**; launching the desktop app
and driving it against a booted emulator through the command palette;
screenshotting and reading the result; calling daemon routes directly with a
token; installing managed tools; decompiling a real APK; connecting the JS
console to a real Metro and evaluating expressions in a running React Native
app.

Add an item here only with a one-line reason it cannot be automated. Delete one
the moment it can be.

---

## 1. Windows and Linux, actually running

**Why not automatable here:** there is no Windows or Linux machine, and no
Windows *container* either — CI compiles both and runs the unit suites.

**Linux is no longer in that sentence.** `desktop-linux-smoke` runs on every PR:
it installs the `.deb` in a bare `ubuntu:24.04` so apt resolves the package's
own declared Depends and nothing else, launches the app under Xvfb, drives the
command palette to open a screen, and photographs both frames. Every check is
fatal, and the artifacts are uploaded whether it passed or not, so a failure is
a picture rather than a description of one. The first run found the app
unusable — a daemon dynamically linked against a Swift runtime no user machine
has — which is the case for the job existing.

What a container **cannot** tell you, and what is left below: whether it looks
right on your GNOME, at your DPI, with your GPU.

- [ ] **Windows: the app launches** and shows a window with the device bar,
      sidebar and tab strip.
- [ ] **Linux on a real desktop** — the deb on a stock GNOME or KDE. That it
      *runs* is now checked on every PR; that its window decorations, fonts and
      DPI look right on a real session is not.
- [ ] **The mirror paints a device.** `scripts/probe-webkit-webcodecs.sh` now
      *decodes* rather than asking: a real Annex-B keyframe goes into WebKitGTK
      and a 64×64 `VideoFrame` comes out — but only with `gstreamer1.0-libav`
      installed, which the `.deb` declares as a Recommends and without which
      the same frame throws "No decoder found". So the codec is settled. What
      is not is a *device* stream: open Mirror Screen with a device attached
      and watch it move.
- [ ] **Native file dialogs open** — Install App, APK Studio's Choose APK,
      and the save-location pickers. These are Rust-side and per-platform.
- [ ] **Fonts and DPI look right** at 100% and at a scaled display.
- [ ] **The menu bar** appears where that OS puts it, and its accelerators fire
      (Ctrl, not ⌘).

## 2. A physical Android device

**Why not automatable here:** only an emulator is attached, and the emulator
cannot be unplugged, cannot pair over Wi-Fi, and does not behave like an OEM
build.

- [ ] **USB connect and disconnect** while the app is open — the device bar
      picks it up and lets it go without a stale selection.
- [ ] **Wireless pairing** (Android 11+): the pairing-code flow in the device
      dropdown, then that the paired device is auto-connected.
- [ ] **USB → Wi-Fi bootstrap** (`adb tcpip`), then unplug and keep working.
- [ ] **An OEM device**, not a Pixel image — Samsung/Xiaomi skins report
      `getprop`, permissions and app lists differently, and that is where
      parsers break.
- [ ] **A rooted device** for Root Status and the Wi-Fi password read.

## 3. More than one device at once

**Why not automatable here:** one emulator. A second one is possible but does
not exercise real per-device timing, and six is not.

- [ ] **Mirror Wall with 2+ devices** — tiles stay independent, quality steps
      down as tiles are added, and dragging a tile's caption strip reorders.
- [ ] **Run on all devices** for a fan-out action, from the device bar.
- [ ] **Take Over / Focus banner** when two windows want the same device.

## 4. Drag and drop

**Why not automatable here:** synthetic drags never fire `dragstart` in a
WKWebView. This is a platform limit, not a missing tool — see the
`webview-drag-not-scriptable` note.

- [ ] **Sidebar reorder** — drag a feature within its group; drag a category
      header to move the whole group. The insertion guideline shows.
- [ ] **Tab drag to split**, and dragging a tab out.
- [ ] **Drop a file** on File Explorer to push it, and an APK on the window to
      install it (once backlog 17 lands — until then, confirm it is refused
      cleanly rather than silently doing nothing).

## 5. Sound

**Why not automatable here:** an agent cannot hear. Whether a file *contains*
audio can be probed; whether it is the right audio, in sync, at a sane level,
cannot.

- [ ] **Record with device audio** — play something on the device, record, then
      listen back.
- [ ] **Record with the Mac microphone** — speak while recording; narration is
      audible and roughly in sync with the picture over a long take.
- [ ] **Both at once** land in *one* track (open the file in QuickTime — a
      second track would be silently dropped by most players).
- [ ] **The level meter** moves when you speak.
- [ ] **Mute mid-take** leaves the timeline continuous, and unmuting is instant.

## 6. macOS permission prompts

**Why not automatable here:** the prompts are system-modal and an agent must
not click through a security dialog on your behalf.

- [ ] **Screen recording**, **microphone**, and **accessibility** prompts appear
      with sensible wording the first time each is needed.
- [ ] Denying one is reported in the app rather than failing silently.

## 7. How it feels

**Why not automatable here:** these are perceptual judgements. A screenshot
cannot tell you a mirror is stuttering or that input lags.

- [ ] **Mirror smoothness and input latency** — tap, swipe and type into a
      mirrored device; it should feel direct.
- [ ] **Light and dark** both read well, including the custom accent and the
      window translucency sliders.
- [ ] **Reduced motion** — with the system setting on, the marketing site's
      scroll reveals and hero demo still work.

## 8. Release mechanics

**Why not automatable here:** signing identities, notarisation, and updating
*from* a previously installed build.

- [ ] **Developer ID signing and notarisation** succeed, and the DMG opens on a
      machine that has never seen the app (Gatekeeper).
- [ ] **The universal binary** really has both slices (`lipo -info`).
- [ ] **Sparkle updates** from the previous release: the pill appears, the
      update stages, and relaunching installs it.
- [ ] **The appcast** points at the artifact that was actually uploaded.
- [ ] A **stable** tag attaches no Windows or Linux artifact
      (`scripts/test-release-channel.sh` asserts this, but confirm the actual
      release page).

## 9. Things needing a real account or endpoint

**Why not automatable here:** no credentials, and an agent should not be
signing in to your services.

- [ ] **API Testing** against a real endpoint that needs auth, and a Postman
      collection exported from a real workspace.
- [ ] **Frida** against a real target — needs a rooted device or a debuggable
      build on hardware.

---

## Known open issues that need an environment I do not have

Not checklist items — findings recorded so they are not rediscovered.

- **`ReactotronRelay.stop()` can return before the listener is released.**
  Surfaced by giving the port test an extra start/stop cycle: it then failed on
  *every* CI run with `Cannot schedule tasks on an EventLoop that has already
  shut down`, and a fresh bind was refused even with `SO_REUSEADDR` set. It does
  not reproduce on this Mac — 30 direct restarts and 12 full-suite runs are
  clean — so it appears to need CI's slower, loaded runner. The port test itself
  was fixed by moving off the ephemeral range; the underlying timing question is
  open. Do not "fix" it without a reproduction: it is a shipping Mac feature.

## A constraint worth knowing

An agent can only drive the GUI while **you are logged in and the display is
awake**. Behind the lock screen Tauri creates no window at all and
`screencapture` fails, so GUI verification stops dead — twice during the work
that produced this file. If you want a session to include hands-on checks,
leave the machine unlocked.
