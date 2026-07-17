.PHONY: generate build test run dmg clean site-dev site-build

# Optional telemetry keys for local builds. Create .env.telemetry (gitignored)
# with SENTRY_DSN=... and POSTHOG_KEY=... to enable crash/analytics locally.
# Without it both stay empty, so neither SDK starts — fine for development.
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
	./scripts/assemble-ffmpeg.sh
	xcodegen generate

build: generate
	xcodebuild -project Droidective.xcodeproj -scheme App -configuration Debug -derivedDataPath DerivedData build $(TELEMETRY)

test:
	cd ADBKit && swift test

run: build
	-pkill -x Droidective
	@sleep 0.3
	open "DerivedData/Build/Products/Debug/Droidective.app"

# One thin DMG, matching what releases ship. ARCH=arm64 (default) or x86_64.
# Each arch bakes its own Sparkle feed, same as the release job.
ARCH ?= arm64
SPARKLE_FEED := $(if $(filter x86_64,$(ARCH)),https://droidective.com/appcast-x86_64.xml,https://droidective.com/appcast.xml)
dmg: generate
	./scripts/assemble-ffmpeg.sh $(ARCH)
	xcodebuild -project Droidective.xcodeproj -scheme App -configuration Release -derivedDataPath DerivedData build ARCHS="$(ARCH)" ONLY_ACTIVE_ARCH=NO SPARKLE_FEED_URL="$(SPARKLE_FEED)" $(TELEMETRY) $(SIGNING)
	./scripts/check-archs.sh DerivedData/Build/Products/Release/Droidective.app $(ARCH)
	SIGN_IDENTITY="$(SIGN_IDENTITY)" ./scripts/package-dmg.sh $(VERSION) $(ARCH)

clean:
	rm -rf DerivedData ADBKit/.build *.xcodeproj

# Marketing site (website/ — React + Vite; site/ is the static passthrough
# copied into the build via Vite's publicDir)
site-dev:
	cd website && npm install && npm run dev

site-build:
	cd website && npm install && npm run build
