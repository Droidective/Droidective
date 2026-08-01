.PHONY: generate build test test-app test-linux run dmg clean site-dev site-build \
	verify verify-fast verify-self \
	test-emulator test-emulator-rooted test-emulator-mirror test-mutation test-smoke

# Optional telemetry keys for local builds. Create .env.telemetry (gitignored)
# with SENTRY_DSN=... and POSTHOG_KEY=... to enable crash/analytics locally.
# Without it both stay empty, so neither SDK starts. That is a genuinely
# different startup path from a keyed build — `SentrySDK.start` is what first
# creates the shared NSApplication — and CI compiles the keyless path without
# ever launching it, so keyless-only launch bugs can hide there.
-include .env.telemetry
TELEMETRY := SENTRY_DSN="$(SENTRY_DSN)" POSTHOG_KEY="$(POSTHOG_KEY)"

# Optional Developer ID signing for `make dmg`. Create .env.signing (gitignored)
# with SIGN_IDENTITY="Developer ID Application: … (TEAMID)" and
# DEVELOPMENT_TEAM=TEAMID for a notarizable build. Without it the DMG is ad-hoc
# signed — fine for local testing, but Gatekeeper still warns.
-include .env.signing
SIGN_IDENTITY ?= -
ifeq ($(SIGN_IDENTITY),-)
SIGNING :=
else
SIGNING := CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp"
endif

generate:
	./scripts/unpack-ffmpeg.sh
	xcodegen generate

build: generate
	xcodebuild -project Droidective.xcodeproj -scheme App -configuration Debug -derivedDataPath DerivedData build $(TELEMETRY)

test:
	cd ADBKit && swift test
	cd ReactotronMCP && swift test
	cd droidectived && swift test

test-app: generate
	xcodebuild test -project Droidective.xcodeproj -scheme AppTests \
	  -destination 'platform=macOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO

# Tiered verification gate — the edit→verify loop. `verify-fast` is tiers 0-1 for
# ADBKit only (no xcodegen, no Xcode); `verify` adds the AppTests bundle. Both
# assert a non-zero swift-testing count, so a suite that discovers nothing fails
# instead of reporting success. `verify-self` tests those guards.
verify-fast:
	./scripts/verify.sh fast

verify: generate
	./scripts/verify.sh all

verify-self:
	./scripts/test-verify-guards.sh
	./scripts/test-release-channel.sh

# Tier 3 — the device-dependent suites against a real emulator. Reuses an
# attached device when there is one and otherwise boots an AVD headless, tearing
# down only what it started. `test-emulator-rooted` uses the rooted AVD for the
# root-gated features; `test-emulator-mirror` adds the scrcpy-backed suites,
# which need a resolvable scrcpy server payload.
test-emulator:
	./scripts/emulator-harness.sh

test-emulator-rooted:
	./scripts/emulator-harness.sh --rooted

test-emulator-mirror:
	./scripts/emulator-harness.sh --filter DeviceLiveTests --filter MirrorTransportLiveTests \
	  --filter MirrorSessionLiveTests --filter ScreenRecorderLiveTests

# Tier 6 — prove the suite has teeth. Breaks real code one mutation at a time and
# asserts `swift test` fails for each; a survivor is a coverage gap. Runs the full
# suite per mutation, so it's for nightly/pre-release, not the edit loop.
test-mutation:
	./scripts/mutation-gate.sh

# Tier 4a — does the built app actually come up? `make build` proves it
# compiles and AppTests proves the pure logic works, but neither catches a
# crash on launch, a missing bundled resource, or a window that never appears.
test-smoke: build
	./scripts/mac-smoke.sh

# The same suite on Linux (see docs/cross-platform.md), via Apple's
# `container` CLI — run `container system start` once per boot. The scratch
# path keeps Linux build artifacts out of the macOS .build.
test-linux:
	container run --rm --cpus 8 --memory 10g \
	  --volume "$(CURDIR)/ADBKit:/src" --workdir /src swift:6.2-noble \
	  bash -c "apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq unzip xz-utils >/dev/null 2>&1; swift test --scratch-path /src/.build/linux"

run: build
	-pkill -x Droidective
	@sleep 0.3
	open "DerivedData/Build/Products/Debug/Droidective.app"

# The generic destination is what makes the build universal: xcodebuild's
# default (the concrete local Mac) builds the active arch only, silently
# dropping the x86_64 slice. package-dmg.sh verifies both slices are present.
dmg: generate
	xcodebuild -project Droidective.xcodeproj -scheme App -configuration Release -destination "generic/platform=macOS" -derivedDataPath DerivedData build $(TELEMETRY) $(SIGNING)
	SIGN_IDENTITY="$(SIGN_IDENTITY)" ./scripts/package-dmg.sh $(VERSION)

clean:
	rm -rf DerivedData ADBKit/.build *.xcodeproj

# Marketing site (website/ — React + Vite; site/ is the static passthrough
# copied into the build via Vite's publicDir)
site-dev:
	cd website && npm install && npm run dev

site-build:
	cd website && npm install && npm run build
