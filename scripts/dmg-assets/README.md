# DMG installer assets

These files style the installer window of `Droidective-<version>.dmg` (the
"drag to Applications" layout). `scripts/package-dmg.sh` assembles the DMG from
them with `hdiutil` — no Finder/AppleScript — so it builds on a headless CI
runner.

| File | Role |
|------|------|
| `make-background.py` | Generates `background@2x.png` (Pillow). |
| `background@2x.png` | The window backdrop (1200×800): "drag and drop" + swoosh arrow. |
| `DS_Store` | Finder-authored window settings: 600×400 window, 128px icons at (150,185)/(450,185), and the background reference. Copied into the volume as `.DS_Store`. |

## Why a committed `.DS_Store`

Finder on recent macOS ignores the synthetic background alias that headless
tools like `dmgbuild` write, so the background never paints. A `.DS_Store`
authored by Finder itself (via `create-dmg`) resolves correctly. We author it
once and commit it; the build just copies it in. Its background alias is keyed
to **volume name `Droidective`** and **`.background/background@2x.png`** — keep
both in sync with `package-dmg.sh` or the background will stop rendering.

## Regenerating

After editing the arrow/text, re-render and re-author the `.DS_Store`:

```sh
# 1. Rebuild the backdrop
uv run --with pillow scripts/dmg-assets/make-background.py

# 2. Re-author the .DS_Store with Finder (needs a GUI session; not CI)
brew install create-dmg
SRC="$(mktemp -d)"; cp -R DerivedData/Build/Products/Debug/Droidective.app "$SRC/"
create-dmg --volname "Droidective" \
  --background scripts/dmg-assets/background@2x.png \
  --window-size 600 400 --icon-size 128 \
  --icon "Droidective.app" 150 185 --app-drop-link 450 185 \
  --no-internet-enable /tmp/_author.dmg "$SRC"
MNT="$(mktemp -d)"; hdiutil attach /tmp/_author.dmg -mountpoint "$MNT" -nobrowse -quiet
cp "$MNT/.DS_Store" scripts/dmg-assets/DS_Store
hdiutil detach "$MNT" -quiet
```
