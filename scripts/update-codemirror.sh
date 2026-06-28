#!/usr/bin/env bash
# Rebuild App/Resources/codemirror-editor.html — the bundled, offline CodeMirror 6
# editor used by the Decompile APK source viewer. Run when bumping CodeMirror.
# Requires Node. The output is a single self-contained HTML (bundle inlined), so
# the app needs no network and no JS build step of its own.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
out="$root/App/Resources/codemirror-editor.html"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp "$here/codemirror/entry.mjs" "$work/entry.mjs"
cd "$work"
printf '%s' '{ "name": "cm-editor-build", "private": true, "type": "module" }' > package.json

npm install --no-audit --no-fund \
  codemirror@^6 \
  @codemirror/state@^6 \
  @codemirror/lang-java@^6 \
  @codemirror/lang-xml@^6 \
  @codemirror/theme-one-dark@^6 \
  @codemirror/search@^6 \
  esbuild

npx esbuild entry.mjs --bundle --minify --format=iife --legal-comments=none --outfile=cm.js

{
  printf '%s' '<!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="dark"><style>html,body{height:100%;margin:0;background:#282c34}.cm-editor{height:100vh}.cm-scroller{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px}</style></head><body><script>'
  cat cm.js
  printf '%s' '</script></body></html>'
} > "$out"

echo "Wrote $out ($(wc -c < "$out") bytes)"
