#!/usr/bin/env bash
# Ask a real WebKitGTK whether it can decode H.264 through WebCodecs.
#
# This is the measurement behind backlog 25's step-0 decision (see
# docs/desktop-parity.md): the mirror decodes in the webview, so the whole
# feature rests on `VideoDecoder` accepting an `avc1.*` config on Linux. The
# answer is not a version check — WebKitGTK's WebCodecs is GStreamer-backed, so
# it depends on which decoder plugins the machine has, and `gstreamer1.0-libav`
# is *not* a dependency of `libwebkit2gtk-4.1-0`.
#
# Run it when a distro bumps WebKitGTK, or before deciding the mirror can drop
# its runtime probe. Two phases, so the result says which half is missing:
# stock install first, then again with the libav decoder added.
#
# Two questions, not one. `isConfigSupported` is a *claim* the webview makes
# from the GStreamer registry; the second phase of each run feeds it a real
# Annex-B keyframe and reports the size of the frame that came out, which is
# what the mirror actually needs to be true.
#
# Expected today (Ubuntu 24.04 / WebKitGTK 2.52.3): every avc1 false and no
# decode in phase A; every avc1 true and a 64x64 frame in phase B.
set -euo pipefail

IMAGE="${IMAGE:-ubuntu:24.04}"
RUNNER="${RUNNER:-}"
if [[ -z "$RUNNER" ]]; then
  for candidate in container docker podman; do
    if command -v "$candidate" >/dev/null 2>&1; then
      RUNNER="$candidate"
      break
    fi
  done
fi
if [[ -z "$RUNNER" ]]; then
  echo "error: need one of container/docker/podman on PATH" >&2
  exit 1
fi

work="$(mktemp -d)"
# Named removals rather than a recursive one: the script knows exactly what it
# created, and `rm -rf` on an expanded variable is the shape worth never having.
trap 'rm -f "$work/probe.py" "$work/run.sh" "$work/sample.h264"; rmdir "$work" 2>/dev/null || true' EXIT

# Kept as a heredoc rather than a committed .py so the probe is one file: it
# only ever runs inside the throwaway container.
cat >"$work/probe.py" <<'PY'
import gi, json
gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gtk, WebKit2, GLib

import os

# A real Annex-B keyframe, base64, produced by ffmpeg just before this runs.
# The point of decoding one is that `isConfigSupported` is a *claim*: WebKitGTK
# answers it from the GStreamer registry, so a plugin that is installed but
# broken, or one that refuses the actual stream, still says yes. A frame that
# comes out the other side with the right dimensions is the answer to the
# question the mirror actually asks.
SAMPLE = os.environ.get("H264_SAMPLE_B64", "")

# `run_javascript` cannot marshal a Promise, so the async work parks its answer
# on `window.__r` and the script's own completion value is a plain string.
KICK = """
window.__r = null;
const SAMPLE = '__SAMPLE__';
(async () => {
  const r = {
    isSecureContext: window.isSecureContext,
    hasVideoDecoder: typeof VideoDecoder !== 'undefined',
    hasVideoFrame: typeof VideoFrame !== 'undefined',
    hasEncodedVideoChunk: typeof EncodedVideoChunk !== 'undefined',
    codecs: {},
    decoded: 'not attempted'
  };
  if (r.hasVideoDecoder) {
    for (const c of ['avc1.42E01E','avc1.4D401F','avc1.640028','vp8']) {
      try {
        const s = await VideoDecoder.isConfigSupported({codec: c});
        r.codecs[c] = !!s.supported;
      } catch (e) { r.codecs[c] = 'threw: ' + e.name; }
    }
    if (SAMPLE) {
      try {
        r.decoded = await decodeOne(SAMPLE);
      } catch (e) { r.decoded = 'threw: ' + (e && e.message ? e.message : String(e)); }
    }
  }
  window.__r = JSON.stringify(r);
})().catch(e => { window.__r = JSON.stringify({fatal: String(e)}); });

// Feed one keyframe through a real decoder and report the frame it produced.
// `description` is deliberately absent: scrcpy sends Annex-B with in-band
// SPS/PPS, which is exactly the shape `VideoDecoder` wants without one, and
// the mirror depends on that being true here.
async function decodeOne(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('no frame within 10s')), 10000);
    const decoder = new VideoDecoder({
      output: (frame) => {
        clearTimeout(timer);
        const answer = frame.codedWidth + 'x' + frame.codedHeight;
        frame.close();
        decoder.close();
        resolve(answer);
      },
      error: (e) => { clearTimeout(timer); reject(e); }
    });
    decoder.configure({ codec: 'avc1.42C029', optimizeForLatency: true });
    decoder.decode(new EncodedVideoChunk({ type: 'key', timestamp: 0, data: bytes }));
    decoder.flush().catch(reject);
  });
}
// The script's own completion value, and it has to be the last statement:
// `run_javascript` marshals it back, and a trailing function declaration is a
// type it refuses with "Unsupported result type".
"kicked";
""".replace("__SAMPLE__", SAMPLE)
POLL = "window.__r === null ? '' : window.__r"

view = WebKit2.WebView()
out = {"v": None}
polls = {"n": 0}

def finish(value):
    out["v"] = value
    Gtk.main_quit()

def on_poll(_src, res, _data):
    try:
        answer = view.run_javascript_finish(res).get_js_value().to_string()
    except Exception as error:
        return finish(json.dumps({"error": "poll: %s" % error}))
    if answer:
        return finish(answer)
    polls["n"] += 1
    if polls["n"] > 100:
        return finish(json.dumps({"error": "async result never arrived"}))
    GLib.timeout_add(100, lambda: (view.run_javascript(POLL, None, on_poll, None), False)[1])

def on_kick(_src, res, _data):
    try:
        view.run_javascript_finish(res)
    except Exception as error:
        return finish(json.dumps({"error": "kick: %s" % error}))
    GLib.timeout_add(100, lambda: (view.run_javascript(POLL, None, on_poll, None), False)[1])

def on_load(_view, event):
    if event == WebKit2.LoadEvent.FINISHED:
        view.run_javascript(KICK, None, on_kick, None)

view.connect("load-changed", on_load)
# A localhost base URI, so `isSecureContext` reflects what the app really gets:
# wry registers its own scheme as secure, so a false here would be the probe's
# fault rather than the platform's.
view.load_html("<html><body>probe</body></html>", "http://localhost/")
GLib.timeout_add_seconds(90, lambda: (finish(json.dumps({"error": "hard timeout"})), False)[1])
Gtk.main()
print("RESULT " + (out["v"] or '{"error":"no result"}'))
PY

cat >"$work/run.sh" <<'SH'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# WebKit cannot reach a GPU or a compositor in here; without these it dies
# before any JavaScript runs.
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_DMABUF_RENDERER=1

# `grep -c` exits non-zero on a count of zero, which is a real answer here and
# not a failure — so every probe below is written to survive pipefail.
h264_elements() {
  gst-inspect-1.0 2>/dev/null | grep -cE 'avdec_h264|openh264dec' || true
}
installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' \
    && echo yes || echo no
}

apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq libwebkit2gtk-4.1-0 gir1.2-webkit2-4.1 python3-gi xvfb \
  gstreamer1.0-plugins-base gstreamer1.0-tools ffmpeg >/dev/null 2>&1

# One real keyframe to decode. Encoded here rather than committed as a blob:
# a base64 string in the repo is a thing nobody can check, and ffmpeg is
# already being installed. 64x64 so the whole sample is a few hundred bytes,
# and `-bf 0 -g 1` so the first access unit is a complete, self-contained IDR
# with its SPS and PPS in band — which is the shape scrcpy sends.
ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=red:s=64x64:d=0.1:r=1 \
  -c:v libx264 -profile:v baseline -bf 0 -g 1 -frames:v 1 -f h264 /work/sample.h264
H264_SAMPLE_B64="$(base64 -w0 /work/sample.h264)"
export H264_SAMPLE_B64
echo "sample keyframe: $(stat -c%s /work/sample.h264) bytes of Annex-B"

echo "webkitgtk: $(dpkg-query -W -f='${Version}' libwebkit2gtk-4.1-0)"
echo "gstreamer1.0-libav arrived as a dependency: $(installed gstreamer1.0-libav)"

echo "--- phase A: stock install"
echo "h264 decoder elements: $(h264_elements)"
xvfb-run -a python3 /work/probe.py 2>/dev/null | grep RESULT

echo "--- phase B: + gstreamer1.0-libav"
apt-get install -y -qq gstreamer1.0-libav >/dev/null 2>&1
echo "h264 decoder elements: $(h264_elements)"
xvfb-run -a python3 /work/probe.py 2>/dev/null | grep RESULT
SH

echo "probing $IMAGE via $RUNNER (installs a webview; takes a few minutes)"
"$RUNNER" run --rm --volume "$work:/work" --workdir /work "$IMAGE" bash /work/run.sh
