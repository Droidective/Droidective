"""Build the macOS -> desktop parity audit from the real sources.

Reads the feature registry (as the daemon serves it), maps each view feature to
the SwiftUI view that renders it, and extracts that view's user-visible
affordances. Generated rather than written by hand so the checklist reflects
what the Mac app actually has.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1])
FEATURES = json.load(open(sys.argv[2]))["features"]
APP = ROOT / "App/Sources"

route_src = (APP / "FeatureDetail/FeatureDetailRoute.swift").read_text()
# case logcat = "logcat"
case_to_id = dict(re.findall(r'case\s+(\w+)\s*=\s*"([^"]+)"', route_src))

pane_src = (APP / "FeatureDetail/FeatureDetailView.swift").read_text()
# `case .logcat:` then the first Capitalised(  constructor after it
id_to_view = {}
blocks = re.split(r"\n\s*case \.", pane_src)
for block in blocks[1:]:
    name = re.match(r"(\w+)", block)
    if not name:
        continue
    view = re.search(r"\b([A-Z]\w*View|[A-Z]\w*Screen|[A-Z]\w*Pane)\b", block[:400])
    if name.group(1) in case_to_id and view:
        id_to_view[case_to_id[name.group(1)]] = view.group(1)

swift_files = {p.stem: p for p in APP.rglob("*.swift")}


def affordances(view_name):
    """User-visible controls in a view, as evidence rather than recollection."""
    path = swift_files.get(view_name)
    if not path:
        return None, []
    text = path.read_text()
    found = []

    def add(kind, label):
        label = label.strip()
        if not label or len(label) > 60:
            return
        # `Button("speaker.wave.1.fill")` is an SF Symbol, not a caption. They
        # mean nothing off Apple and must not become checklist items.
        if re.fullmatch(r"[a-z0-9]+(\.[a-z0-9]+)+", label):
            return
        entry = f"{kind}: {label}"
        if entry not in found:
            found.append(entry)

    for m in re.finditer(r'Button\(\s*"([^"]{2,60})"', text):
        add("button", m.group(1))
    for m in re.finditer(r'Toggle\(\s*"([^"]{2,60})"', text):
        add("toggle", m.group(1))
    for m in re.finditer(r'Picker\(\s*"([^"]{2,60})"', text):
        add("picker", m.group(1))
    for m in re.finditer(r'Menu\(\s*"([^"]{2,60})"', text):
        add("menu", m.group(1))
    for m in re.finditer(r'TextField\(\s*"([^"]{2,60})"', text):
        add("field", m.group(1))
    for m in re.finditer(r'Label\(\s*"([^"]{2,60})"', text):
        add("label", m.group(1))
    for m in re.finditer(r'\.help\(\s*"([^"]{2,60})"', text):
        add("tooltip", m.group(1))
    if ".searchable" in text:
        add("search", "searchable list")
    if ".contextMenu" in text:
        add("menu", "right-click context menu")
    for m in re.finditer(r'\.keyboardShortcut\(([^)]{1,40})\)', text):
        add("shortcut", m.group(1))
    if "onDrag" in text or "onDrop" in text:
        add("drag", "drag and drop")
    if "exportTo" in text or "fileExporter" in text or "askSaveLocation" in text:
        add("export", "save/export to a file")
    return path.relative_to(ROOT), found


# The only two features that genuinely cannot exist off Apple: both drive an
# iOS Simulator through `xcrun simctl`, which is a macOS toolchain rather than
# anything about the device. Everything else the port lacks is a porting job
# with a plan in the tracker's backlog, not an exclusion — a ⛔ that means
# "hard" rather than "impossible" reads as a decision nobody has to revisit.
GATED = {
    "ios-logs": "iOS Simulator only, via simctl — a macOS toolchain, not a device.",
    "push-notification": "iOS Simulator only (simctl push).",
}

# Not started, and big enough that the checklist alone understates them. The
# note says what each actually needs so the entry is a plan, not a shrug.
BLOCKED = {
    "scrcpy": "Not started — the decode/render stack needs writing off Apple "
              "(scrcpy's server is portable; VideoToolbox/AVFoundation are not). Backlog 25.",
    "screen-record": "Not started — rides the mirror session, so it follows the mirror. Backlog 25.",
    "video-editor": "Not started — needs the mirror pipeline plus the bundled ffmpeg. Backlog 25.",
    "reactotron": "Not started — blocked on porting the relay's Network.framework "
                  "listener to NIO, which ReactotronMCP already proves out. Backlog 24.",
}

by_category = {}
for feature in FEATURES:
    by_category.setdefault(feature["category"], []).append(feature)

CATEGORY_TITLES = {
    "input": "Input & Clipboard",
    "connection": "Connection",
    "reactNative": "React Native",
    "screen": "Screen & Capture",
    "deviceState": "Device State",
    "appManagement": "App Management",
    "logs": "Logs & Diagnostics",
    "toolUX": "Tool UX",
}

out = []
counts = {"done": 0, "partial": 0, "todo": 0, "gated": 0}
rows = []

for category, features in by_category.items():
    out.append(f"\n### {CATEGORY_TITLES.get(category, category)}\n")
    for f in sorted(features, key=lambda x: x["id"]):
        fid = f["id"]
        kind = f["kind"]
        if fid in GATED:
            status, note = "⛔ n/a", GATED[fid]
            counts["gated"] += 1
        elif fid in BLOCKED:
            status, note = "⬜ todo", BLOCKED[fid]
            counts["todo"] += 1
        elif fid in ("apps", "logcat", "file-explorer", "crash-catcher"):
            status, note = "🟡 partial", "A pane exists; the checklist below is what it is missing."
            counts["partial"] += 1
        elif kind in ("instantAction", "formAction", "toggleAction") and f["implemented"]:
            status, note = "🟡 partial", "Runs from the palette; no dedicated screen."
            counts["partial"] += 1
        elif not f["implemented"]:
            status, note = "⬜ todo", "Not implemented on macOS either."
            counts["todo"] += 1
        else:
            status, note = "⬜ todo", "Not started on Windows/Linux."
            counts["todo"] += 1

        rows.append((fid, status))
        out.append(f"#### `{fid}` — {f['title']}  ·  {status}\n")
        if f["subtitle"]:
            out.append(f"> {f['subtitle']}\n")
        out.append(f"- **Kind** `{kind}`"
                   + (" · **hub member**" if f["isAbsorbedByHub"] else "")
                   + (" · **destructive**" if f["isDestructive"] else "")
                   + (" · **needs an app**" if f["needsBundle"] else "") + "\n")
        out.append(f"- **Note** {note}\n")

        if f["fields"]:
            names = ", ".join(
                f"`{x['name']}` ({x['control']}{'' if not x['optional'] else ', optional'})"
                for x in f["fields"])
            out.append(f"- **Parameters** {names}\n")

        view = id_to_view.get(fid)
        # A gated feature gets no checklist: there is nothing to replicate.
        if view and fid not in GATED:
            path, controls = affordances(view)
            out.append(f"- **macOS view** `{view}`"
                       + (f" — `{path}`" if path else " — *(file not found)*") + "\n")
            if controls:
                out.append("- **Must replicate**\n")
                for c in controls:
                    out.append(f"  - [ ] {c}\n")
            else:
                out.append("  - [ ] *(no controls auto-detected — audit by hand)*\n")
        out.append("\n")

print("".join(out))
print("<!-- counts:", counts, "-->")
