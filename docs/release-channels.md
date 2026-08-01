# Release channels

Droidective ships on two channels from one `main` branch. The tag decides
which.

| | **stable** | **beta** |
| --- | --- | --- |
| Tag | `vX.Y.Z` | `vX.Y.Z-beta.N` (any pre-release suffix) |
| GitHub release | normal | prerelease |
| macOS | ✅ signed, notarized DMG | ✅ same DMG |
| Windows | ❌ | ✅ `droidectived` (the Tauri app when it exists) |
| Linux | ❌ | ✅ `droidectived` (the Tauri app when it exists) |
| Update feed | `appcast.xml`, untagged item | `appcast.xml` beta item **+** `updates/beta/latest.json` |
| Who gets it | every install | Settings ▸ General ▸ Updates ▸ *Receive beta updates*, and Windows/Linux users |

The Windows and Linux rows describe what a beta tag carries **once there is
something to carry** — today that is nothing, because no Windows or Linux
binary exists yet. See [Where this stands](#where-this-stands); the policy and
its enforcement are in place now so the artifacts have a home the day they
build.

**The rule, in one sentence:** the stable channel is macOS-only and always will
be until a non-Apple platform is good enough to graduate; everything
cross-platform lives on beta.

This is a standing arrangement, not a pre-release cycle. Windows and Linux are
expected to sit on beta for a long time, and a beta that ships them is not a
promise that the next stable will.

## Tag grammar

One rule, matching what the pipeline already keyed on: **a hyphen in the tag
means pre-release.**

```
v3.8.0          → stable   → macOS DMG only
v3.9.0-beta.1   → beta     → DMG + Windows + Linux
v3.9.0-beta.2   → beta     → DMG + Windows + Linux
v3.9.0          → stable   → macOS DMG only
```

`scripts/release-channel.sh <tag>` is the single resolver — it prints the
channel and the exact artifact set expected for it, and every other step reads
from it rather than re-deriving the rule. `scripts/test-release-channel.sh`
unit-tests it (the `test-verify-guards.sh` pattern): the channel policy is a
test, not review folklore.

## Why one version line

The alternative — a separate `xplat-vA.B.C` line for Windows/Linux — was
rejected. It buys an honest signal that the ports lag in features, and costs
two changelogs, two version-touchpoint tables, two feed lifecycles, and a
standing "how does Windows 0.3 relate to Mac 3.9?" question. One line with a
`-beta.N` suffix carries the same "this is rougher" signal at a fraction of the
machinery, and it leaves the existing Sparkle beta channel's meaning untouched.

So a beta is exactly *the next stable's Mac build, plus the cross-platform
builds*. A beta cut purely to ship a Windows fix still rebuilds the Mac app;
that is a harmless rebuild, not a Mac release.

## The two feeds

macOS updates through Sparkle; Windows and Linux never will. They are separate
files on purpose — `update-appcast.sh` rewrites the appcast wholesale, and
interleaving a second platform's state into it would make both fragile.

### `site/appcast.xml` — macOS, Sparkle

Unchanged by this policy. A stable tag writes one untagged item; a beta tag
writes an item carrying `<sparkle:channel>beta</sparkle:channel>` and preserves
the current stable item alongside it. Shipping the stable afterwards drops the
beta item and beta installs move up to it via the monotonic run-number
`CFBundleVersion`.

That lifecycle stays correct here because the Mac beta still means "pre-release
of the next Mac stable". The cross-platform artifacts riding the same tag are
invisible to Sparkle.

### `site/updates/beta/latest.json` — Windows and Linux

Written on beta tags only, committed to `main` by the release job (the same
route the appcast takes, so Pages deploys it), and never written by a stable
tag — a stable release leaves the previous beta feed in place, because the
newest beta is still the newest thing Windows and Linux have.

```jsonc
{
  "version": "3.9.0-beta.1",
  "tag": "v3.9.0-beta.1",
  "pubDate": "2026-08-09T10:04:11Z",
  "notesUrl": "https://github.com/Droidective/Droidective/releases/tag/v3.9.0-beta.1",
  "artifacts": {
    "windows-x86_64": { "url": "https://…/droidectived-3.9.0-beta.1-windows-x86_64.zip",
                        "sha256": "…" },
    "linux-x86_64":   { "url": "https://…/droidectived-3.9.0-beta.1-linux-x86_64.tar.gz",
                        "sha256": "…" }
  }
}
```

This is our own shape, consumed by the website's beta section. It is
deliberately **not** a Tauri updater manifest yet: that format's `signature`
field is a minisign signature the updater verifies, and emitting an empty or
placeholder one would leave a hole for whoever later points a real updater at
this URL. When the Tauri app lands it gets its own signed feed next to this one
(`updates/beta/tauri.json`), generated with the real key.

Why a committed static file at all, rather than the site querying GitHub's
releases API for the newest prerelease: no runtime API dependency, no rate
limit, no unauthenticated-CORS problem, and it matches how the appcast already
works.

## What each channel must and must not touch

The release checklist's version touchpoints are **not** the same for both
channels. A beta that bumps the site's stable version advertises a pre-release
as the current release.

| touchpoint | stable | beta |
| --- | --- | --- |
| `RELEASE_NOTES.md` — new `## Droidective vX.Y.Z` section | ✅ | ✅ (heading carries the full tag, e.g. `v3.9.0-beta.1`) |
| `project.yml` `MARKETING_VERSION` | ✅ | ❌ — CI passes the tag's version to `xcodebuild`, overriding it; the file tracks the stable line |
| `website/src/lib/content.ts` `APP_VERSION` | ✅ | ❌ — drives the hero badge and JSON-LD `softwareVersion`, both of which mean *current stable* |
| `website/src/lib/content.ts` `releases` entry | ✅ | ❌ — the public changelog is the stable line |
| `BETA_VERSION` + beta section copy | ❌ | ✅ |
| `CLAUDE.md` Status | ✅ | only if the beta changed something a future session needs to know |
| `site/sitemap.xml` `<lastmod>` | ✅ | ✅ if the beta section changed |
| `site/appcast.xml` | never by hand — CI owns it | never by hand — CI owns it |
| `site/updates/beta/latest.json` | never written | never by hand — CI owns it |

## Release notes are selected by tag, not by position

The old extraction took the **first** `## ` section of `RELEASE_NOTES.md`. That
couples the file's ordering to the release order, which breaks the moment a
long-lived beta line interleaves with stable: prepare `v3.9.0-beta.1` notes,
then need a `v3.8.1` Mac hotfix, and you have to shuffle sections around the
tag and shuffle them back.

`scripts/extract-notes.sh <tag>` finds the section whose heading matches the
tag and fails loudly if there isn't one. Section order in the file is now
purely editorial.

## Signing and trust, per platform

| | state |
| --- | --- |
| macOS | Developer ID + notarization + stapling, both channels. No change. |
| Linux | Unsigned tarballs with published SHA-256 sums. Normal for the ecosystem. |
| Windows | **Unsigned for the beta.** SmartScreen will warn; the beta download page says so and gives the "More info → Run anyway" steps. |

Windows Authenticode is a deliberate deferral, not an oversight: an OV
certificate is a recurring cost and a multi-week identity-validation process,
and reputation accrues per-certificate over download volume a beta will not
generate quickly. Revisit it when Windows is a candidate to leave beta —
Azure Trusted Signing is the cheapest current route for an individual
publisher, and it needs its own decision, not a default.

## Where this stands

Phase 1 of the port is on `main`: ADBKit compiles and tests on macOS, Linux,
and Windows, and `PortabilityGuardTests` keeps it that way. See
`cross-platform.md`.

There is no Windows or Linux **application** yet, so the first beta payload is
`droidectived` — the daemon from `droidectived-protocol.md`. Headless, but
genuinely useful on its own (CI, scripting, remote adb over loopback), and it
puts the whole cross-platform build-package-publish-feed path under load months
before the Tauri UI depends on it.

| stage | payload of a beta tag | status |
| --- | --- | --- |
| 0 | Mac DMG only (channel infra in place, no cross-platform artifact) | ← here |
| 1 | \+ `droidectived` for Windows, Linux, macOS | daemon scaffold landed; protocol unimplemented |
| 2 | \+ the Tauri app for Windows and Linux, with its signed updater feed | not started |

macOS's stable channel is unaffected at every stage. That is the point of the
split: the port cannot regress the thing people use today, because the thing
people use today never ships from a beta tag.

## Traps

- **`fail_on_unmatched_files` and a varying artifact set.** A static `files:`
  glob listing Windows artifacts fails every stable release. Artifacts are
  staged into `dist/` by `scripts/stage-release-artifacts.sh`, which asserts
  the exact expected set for the channel and lets the publish step glob
  `dist/*`. The assertion is stronger than the glob it replaces: a missing DMG
  now fails with the reason, not with "unmatched pattern".
- **`/releases/latest/download/Droidective.dmg` is prerelease-safe.** GitHub's
  `latest` never resolves to a prerelease, so the site's download button keeps
  serving the newest stable throughout a beta cycle. Windows and Linux have no
  equivalent permanent URL — they resolve through `latest.json`, which is why
  that file exists.
- **The daemon package is macOS-gated on the branch it lives on.** On
  `feat/droidectived-scaffold` (not yet merged), `droidectived/Package.swift`
  declares `platforms: [.macOS(.v14)]`, and its CI additions run the daemon
  suite on macOS and Linux but not Windows — the one component whose entire
  purpose is serving Windows and Linux is not built on Windows. Fix that when
  landing the scaffold, before stage 1.
- **A beta must not be the newest `## ` section by accident.** With tag-aware
  extraction this is no longer load-bearing, but the file still reads
  top-down for humans; keep stable sections in version order and betas next to
  the stable they precede.
