# Third-party notices

## scrcpy-server

`App/Resources/scrcpy-server` is the device-side server from
[scrcpy](https://github.com/Genymobile/scrcpy) (v4.1), bundled and pushed to the
device so the in-app screen mirror works without a separate scrcpy install.

- Project: scrcpy — Copyright (C) 2018 Genymobile / Romain Vimont
- License: Apache License 2.0 — https://github.com/Genymobile/scrcpy/blob/master/LICENSE

The binary is redistributed unmodified under the terms of the Apache License 2.0.
Droidective speaks scrcpy's protocol with its own client; only the server payload
is bundled.

## ffmpeg

`App/Resources/ffmpeg.zip` holds a static build of [ffmpeg](https://ffmpeg.org)
(v8.1.2, macOS universal — arm64 + x86_64; committed compressed because the raw
binary exceeds GitHub's file size limit, unpacked into the app bundle at build
time), bundled and run on the Mac to power the video editor's exports
(trim/crop/rotate/scale/speed and mp4/mov/mkv/webm/gif encoding) without a
separate ffmpeg install.

- Project: FFmpeg — https://ffmpeg.org
- License: **GNU General Public License v3** (this build is configured with
  `--enable-gpl --enable-version3`, which includes GPL components such as
  libx264/libx265). The full license text is at https://www.gnu.org/licenses/gpl-3.0.html
- Build source: https://ffmpeg.martin-riedl.de (macOS arm64 + x86_64 "release"
  builds, combined into one universal binary with `lipo`)
- The pinned per-slice SHA-256s in `scripts/update-bundled-tools.sh` are the
  source of truth for the exact bundled build; update the version stated above
  whenever that script refreshes the binary.
- The binary is redistributed unmodified. FFmpeg's source is available from
  https://ffmpeg.org/download.html and https://git.ffmpeg.org/ffmpeg.git

Because this ffmpeg build is GPLv3, distributing the app bundle with it included
carries GPLv3 obligations. Droidective invokes ffmpeg only as a separate
executable (via `Process`) and never links against it or its libraries, so the
app and ffmpeg are aggregated rather than a combined/derivative work — the app's
own MIT license is unaffected. The obligation is to make ffmpeg's corresponding
source and license available to recipients, which the upstream links above
satisfy; the unmodified binary is redistributed under GPLv3.

## bundletool

`App/Resources/bundletool-all.jar` is [bundletool](https://github.com/google/bundletool)
(v1.18.3), Google's command-line tool for Android App Bundles, bundled and run
via `java -jar` on the Mac so the AAB to APK feature converts `.aab` files to
universal APKs with no first-use download (a copy is seeded into
Application Support's managed tools, where Settings ▸ Tools can upgrade it).

- Project: bundletool — Copyright Google LLC
- License: Apache License 2.0 — https://github.com/google/bundletool/blob/master/LICENSE
- The pinned SHA-256 in `scripts/update-bundled-tools.sh` is the source of
  truth for the exact bundled jar; the jar is redistributed unmodified under
  the terms of the Apache License 2.0.

## uber-apk-signer

`App/Resources/uber-apk-signer.jar` is [uber-apk-signer](https://github.com/patrickfav/uber-apk-signer)
(v1.3.0), bundled and seeded into Application Support's managed tools so APK
signing helpers work with no first-use download.

- Project: uber-apk-signer — Copyright Patrick Favre-Bulle
- License: Apache License 2.0 — https://github.com/patrickfav/uber-apk-signer/blob/main/LICENSE
- The pinned SHA-256 in `scripts/update-bundled-tools.sh` is the source of
  truth for the exact bundled jar; the jar is redistributed unmodified under
  the terms of the Apache License 2.0.

## CodeMirror

`App/Resources/codemirror-editor.html` bundles a built, offline copy of
[CodeMirror 6](https://codemirror.net) (the `codemirror`, `@codemirror/state`,
`@codemirror/lang-java`, `@codemirror/lang-xml`, `@codemirror/theme-one-dark`,
and `@codemirror/search` packages, assembled by
`scripts/update-codemirror.sh`), used by the Decompile APK source viewer.

- Project: CodeMirror — Copyright (C) 2018-2021 by Marijn Haverbeke
  <marijn@haverbeke.berlin> and others
- License: MIT — https://github.com/codemirror/view/blob/main/LICENSE
  (text reproduced below)

## Sparkle

The [Sparkle](https://sparkle-project.org) framework is embedded in the app
bundle (via Swift Package Manager) to power automatic updates.

- Project: Sparkle — Copyright (c) 2006-2013 Andy Matuschak; Copyright (c)
  2009-2013 Elgato Systems GmbH; Copyright (c) 2011-2014 Kornel Lesiński;
  Copyright (c) 2015-2017 Mayur Pawashe; Copyright (c) 2014 C.W. Betts;
  Copyright (c) 2014 Petroules Corporation; Copyright (c) 2014 Big Nerd Ranch.
  All rights reserved.
- License: MIT — https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE
  (text reproduced below). Sparkle's LICENSE additionally covers third-party
  code it embeds (bsdiff/bspatch under the BSD license, a portable Ed25519
  implementation under Zlib, and others) — see that file for the full texts.

## Sentry

The [sentry-cocoa](https://github.com/getsentry/sentry-cocoa) SDK is embedded
in the app bundle (via Swift Package Manager) for anonymous crash reporting
(opt-out in Settings → Privacy).

- Project: Sentry — Copyright (c) 2015 Sentry
- License: MIT — https://github.com/getsentry/sentry-cocoa/blob/main/LICENSE.md
  (text reproduced below)

## PostHog

The [posthog-ios](https://github.com/PostHog/posthog-ios) SDK is embedded in
the app bundle (via Swift Package Manager) for anonymous product analytics
(opt-out in Settings → Privacy).

- Project: PostHog — Copyright (c) 2023 PostHog
- License: MIT — https://github.com/PostHog/posthog-ios/blob/main/LICENSE
  (text reproduced below)

## KeyboardShortcuts

The [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
framework is embedded in the app bundle (via Swift Package Manager) to power
the global and per-feature hotkeys.

- Project: KeyboardShortcuts — Copyright (c) Sindre Sorhus
  <sindresorhus@gmail.com> (https://sindresorhus.com)
- License: MIT — https://github.com/sindresorhus/KeyboardShortcuts/blob/main/license
  (text reproduced below)

## SwiftTerm

The [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) framework is
embedded in the app bundle (via Swift Package Manager) to power the built-in
terminal.

- Project: SwiftTerm — Copyright (c) 2019-2022 Miguel de Icaza
  (https://github.com/migueldeicaza); Copyright (c) 2017-2019, The xterm.js
  authors (https://github.com/xtermjs/xterm.js); Copyright (c) 2014-2016,
  SourceLair Private Company (https://www.sourcelair.com); Copyright (c)
  2012-2013, Christopher Jeffrey (https://github.com/chjj/)
- License: MIT — https://github.com/migueldeicaza/SwiftTerm/blob/main/LICENSE
  (text reproduced below)

## MIT license text

The CodeMirror, Sparkle, Sentry, PostHog, KeyboardShortcuts, and SwiftTerm
components above are each redistributed under the MIT license — the following
text, with the copyright notice given in each component's section:

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to
> deal in the Software without restriction, including without limitation the
> rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
> sell copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
> FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
> IN THE SOFTWARE.
