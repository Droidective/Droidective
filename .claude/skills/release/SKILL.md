---
name: release
description: Cut a Droidective release — every version touchpoint (project.yml, notes, website, docs, sitemap), what CI owns, the merge-then-tag flow, and post-release verification. Use when asked to release, prepare a version, or bump the app version.
---

# Releasing Droidective vX.Y.Z

RELEASING.md is the authority (setup, secrets, beta channel) and
`docs/release-channels.md` owns the channel policy; this is the operational
checklist. Work on a `release/vX.Y.Z` branch off latest `origin/main`, one
"Prepare vX.Y.Z release" commit, PR to main.

**Which channel?** `vX.Y.Z` is stable and **macOS-only**. `vX.Y.Z-beta.N` is
beta and additionally carries the Windows and Linux builds. That decides which
touchpoints below apply — a beta skips the ones marked *(stable only)*, because
`APP_VERSION` and the site changelog mean *current stable release*.
`./scripts/release-channel.sh artifacts <tag>` prints exactly what a tag will
publish; CI asserts the same set before uploading.

## 0. Pre-flight

- `git fetch origin` — releases are CI-driven and local main drifts.
- Every feature PR meant for this release is **merged to main first**; the
  notes must describe only what the tag will contain.
- `cd ADBKit && swift test` green (no skips), `make build` zero warnings,
  changed features verified live (the `verify` skill).

## 1. Version touchpoints

**stable** does all of these; **beta** skips the ones marked ❌ (they mean
*current stable release*, which a pre-release is not).

| file | change | beta |
|---|---|---|
| `project.yml` | `MARKETING_VERSION: "X.Y.Z"` | ❌ CI passes the tag's version to xcodebuild; the file tracks the stable line |
| `RELEASE_NOTES.md` | new `## Droidective <tag>` section (summary paragraph, themed `###` sections with bold leads, `### Install` last). `extract-notes.sh` matches the heading against the tag, so the exact tag must appear in it and position no longer matters — plain factual language, no superlatives | ✅ |
| `website/src/lib/content.ts` | `APP_VERSION = "vX.Y.Z"` **and** a new entry at the head of `releases` (one-paragraph HTML, `latest: true`; move `latest` off the previous entry). Drives the hero badge, the site changelog, and the build-time JSON-LD `softwareVersion` | ❌ |
| `CLAUDE.md` | Status section: new "(Latest release: **vX.Y.Z** — …)" entry, previous release shifts into the "Before that" chain; test count if it moved | only if it changed something a future session needs |
| `README.md` / `docs/` | only if features or counts changed (registry total, marketing copy) | ✅ |
| `site/sitemap.xml` | `<lastmod>` on `/` and `/changelog/` → release date | only if the beta section changed |
| screenshots | if the UI changed visibly: refresh the affected `site/assets/screenshot-*.webp` (1512×948 window, default layout, demo-safe device content) and regenerate og:image PNGs via `sips -s format png <in>.webp --out <out>.png`. Needs a human-quality pass — flag it rather than shipping wrong captures | ❌ |

Verify the website compiles: `cd website && npm run build`.

## 2. Do NOT touch

- `site/appcast.xml` — the CI release job signs and commits it to main.
- `site/updates/beta/latest.json` — same, on beta tags only.
- `"softwareVersion"` in `website/index.html` — a placeholder; vite's
  `transformIndexHtml` injects `APP_VERSION` at build time.
- `DOWNLOAD_URL` — the permanent `releases/latest/download/Droidective.dmg`
  link; never versioned.
- `CFBundleVersion` — CI sets it to the Actions run number.

## 3. Land and tag

1. Push the branch, open the PR with RELEASING.md's checklist pasted in and
   ticked honestly (leave undone items unticked with a reason).
2. Merge every feature PR, then the release PR. Merging needs a review or
   the admin bypass — that's the user's action, not the agent's.
3. Tag the post-merge main head and push — this is the release trigger:
   ```sh
   git fetch origin && git tag vX.Y.Z origin/main && git push origin vX.Y.Z
   ```
   A `-beta.N` suffix publishes to the beta channel instead (see
   RELEASING.md).

CI then builds/signs/notarizes the DMG, publishes the GitHub release with
the notes, and commits the signed appcast to main, which redeploys Pages.

## 4. Verify after CI finishes

- GitHub release: right version, notes rendered, DMG attached — and for a
  stable tag, **nothing else** attached. The stable channel is macOS-only.
- `spctl -a -vvv -t install Droidective-vX.Y.Z.dmg` → accepted, Notarized
  Developer ID.
- `https://droidective.com/` shows the new badge + changelog entry;
  `appcast.xml` lists the version with a `sparkle:edSignature` and inline
  notes.
- A prior install offers and applies the Sparkle update. Debug-build gotcha:
  never test updates with two instances running, and remember Sparkle is
  disabled in Debug builds by design.

## Known traps

- The user's `gh` remote alias may not be `github.com` — resolve
  `owner/name` explicitly (`Droidective/Droidective`) on every `gh` call.
- The pre-push hook blocks any command string matching `git push … main` —
  keep pushes and `gh pr create --base main` in separate Bash calls.
- The notes describe merged reality: if a feature PR is still open, say so
  in the release PR body and hold the tag until it lands.
- The notes heading must contain the exact tag. `extract-notes.sh` fails the
  release rather than guessing, which is the point — but it fails *after* the
  build, sign, and notarize steps have already run.
- macOS ships bash 3.2, and so does the `macos-15` runner: no `mapfile`, no
  associative arrays in the release scripts.
