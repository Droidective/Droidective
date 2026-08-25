# Release channels

Droidective ships on two channels from one `main` branch. The tag decides
which.

| | **stable** | **beta** |
| --- | --- | --- |
| Tag | `vX.Y.Z` | `vX.Y.Z-beta.N` (any pre-release suffix) |
| GitHub release | normal | prerelease |
| Version | `X.Y.Z` — the Mac's line | Mac `X.Y.Z-beta.N`, ports `PORT_VERSION` |
| macOS | ✅ signed, notarized DMG | ✅ same DMG |
| Windows | ❌ | ✅ NSIS installer, MSI, and `droidectived` |
| Linux | ❌ | ✅ `.deb`, `.AppImage`, and `droidectived` |
| Update feed | `appcast.xml`, untagged item | `appcast.xml` beta item **+** `updates/beta/latest.json` |
| Who gets it | every install | Settings ▸ General ▸ Updates ▸ *Receive beta updates*, and Windows/Linux users |

The Windows and Linux rows are what a beta tag carries today. See
[Where this stands](#where-this-stands) for how it got here.

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

## Two version lines

The Mac and the ports are versioned **separately**, and the tag carries only
the Mac's.

```
tag                 Mac DMG           Windows + Linux
v3.9.2              3.9.2             — (stable is macOS-only)
v3.10.0-beta.1      3.10.0-beta.1     PORT_VERSION, e.g. 0.0.1-beta.1
v3.10.0-beta.2      3.10.0-beta.2     PORT_VERSION, bumped or not
```

The Mac carries the product's own history — 61 features across three major
versions — and the ports do not. Naming a first Windows build `3.10.0` claims a
maturity it has not got: someone downloading it reads the version as "the tenth
minor release of a mature app", and what they get is a port with 17 of those 61
features not started.
`0.0.1-beta.1` says the true thing without a paragraph of explanation.

**Where each version lives.** The tag names the Mac's, exactly as before.
`PORT_VERSION` at the repo root names the ports', and is bumped by hand like
`MARKETING_VERSION`. `release-channel.sh` reads both — `port-version` and
`msi-version` — so the rule stays in one resolver and
`test-release-channel.sh` can assert that the two never cross: the Mac's
version must never name a port artifact, and the ports' must never name the
DMG. That pair of tests is the whole design.

**It must be semver.** Tauri rejects anything else, and every bundler derives
its own version from it. `0.0.1_beta` is not semver — an underscore is not a
pre-release separator — and `release_port_version` refuses it by name rather
than letting the build fail later with something less obvious. WiX is the one
exception that needs help: an MSI version must be numeric
`major.minor.patch[.build]`, so `msi-version` strips the pre-release suffix and
the build passes it as `bundle.windows.wix.version`.

**What this costs, and it is not nothing.** This reverses the earlier decision
to keep one version line, which was taken to avoid exactly these costs: two
things to bump instead of one, two histories a reader has to relate, and the
standing question of how Windows 0.0.1 relates to Mac 3.10. The answer to that
question is "it does not, deliberately" — the ports are their own product until
one of them is good enough to graduate. The mitigation for the rest is that
neither version is written down twice: the tag is the Mac's only source and
`PORT_VERSION` is the ports' only source, and a release that gets them
backwards fails its own test suite rather than shipping.

A beta is still *the next Mac stable's build plus the cross-platform builds*.
A beta cut purely to ship a Windows fix still rebuilds the Mac app; that is a
harmless rebuild, not a Mac release, and `PORT_VERSION` may move without the
tag's minor moving at all.

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

**Not implemented.** This section is the design, not a description of the
pipeline: nothing in the release job writes this file today, and the website has
no beta section to read it. Until both exist, the GitHub prerelease page is
where Windows and Linux downloads live, and the permanent
`/releases/latest/download/` link keeps serving the newest *stable* Mac build
throughout a beta cycle because GitHub's `latest` never resolves to a
prerelease.

The design, for whoever builds it: written on beta tags only, committed to
`main` by the release job (the same route the appcast takes, so Pages deploys
it), and never written by a stable tag — a stable release leaves the previous
beta feed in place, because the newest beta is still the newest thing Windows
and Linux have.

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
| `PORT_VERSION` | ❌ — a stable publishes nothing it names | ✅ if the Windows/Linux build changed since the last beta |
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
| 0 | Mac DMG only (channel infra in place, no cross-platform artifact) | done |
| 1 | \+ `droidectived` for Windows, Linux, macOS | done — protocol implemented |
| 2 | \+ the Tauri app for Windows and Linux | ← here, unsigned; no updater feed yet |
| 3 | \+ a signed Tauri updater feed | not started (see `latest.json` above) |

`CROSS_PLATFORM_STAGE` in `release-channel.sh` is the switch, and every stage
is a test: the suite asserts what each one publishes and — more importantly —
that raising it never leaks a port artifact onto the stable channel.

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
- **The daemon's suite does not run on Windows, only its build does.** The
  scaffold has landed, and `droidectived/Package.swift` still declares
  `platforms: [.macOS(.v14)]` — harmless, because that clause sets an Apple
  deployment target and does not restrict which hosts can build the package.
  What is real is the coverage gap: the suite runs in `test` (macOS) and
  `test-linux`, while `build-windows` only compiles the daemon. So the component
  whose entire purpose is serving Windows is the one nobody tests there, and a
  Windows-only behaviour difference — a path separator, a socket option, a
  handle still held at teardown — surfaces in a beta rather than in CI. The two
  Windows-only failures already on record (`ERROR_SHARING_VIOLATION` in temp-dir
  teardown, and `AabConvertServiceTests`) are that shape.
- **The two version lines are one substitution away from crossing.** Every
  cross-platform artifact name must come from `release-channel.sh port-version`,
  never from `${GITHUB_REF_NAME#v}` — that expression is right for the DMG and
  wrong for everything else, and it is the natural thing to type. Two tests
  exist purely to catch it (`the Mac's version never names a port artifact` and
  its mirror), because the failure ships a correctly-built binary under a name
  that claims it is the Mac release.
- **A beta must not be the newest `## ` section by accident.** With tag-aware
  extraction this is no longer load-bearing, but the file still reads
  top-down for humans; keep stable sections in version order and betas next to
  the stable they precede.
