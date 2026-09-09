# Telemetry audit

What Droidective collects, what guarantees it, what it can and cannot answer,
and what is still unmeasured. Current as of the observability pass that added
`MemoryLedger`, `WorkloadCensus`, `UsageWindow` and `TelemetryScrub`.

Two sinks, both **on by default**, both opt-out in Settings ▸ Privacy:

| sink | what for | identity |
|---|---|---|
| Sentry (`de.sentry.io`, `ro-is/droidective-mac`) | crashes, app hangs, structured logs, resource warnings | `user.id` = install UUID |
| PostHog (`us.posthog.com`, project 478882) | product analytics, resource events | `distinct_id` = the same UUID |

The identifier is a random UUID generated once per install (`analyticsDeviceID`
in UserDefaults). It is not derived from anything about the machine or the
person, and it is the only stable identifier sent. Because both sinks use it,
an install found in one can be joined exactly in the other.

---

## 1. Privacy — what is guaranteed and by what

The promise in Settings ▸ Privacy and the privacy policy is: no device serials,
package ids, file paths, URLs, IPs, or command contents.

**Until this pass that promise was call-site discipline.** `Telemetry.track`
takes `[String: Any]`; any one of ~15 call sites could have passed a path and
nothing would have noticed. That is the same shape of hazard as a missing
`shellQuote`, and it had already been paid for once: Sentry's
`enableCaptureFailedRequests` was capturing the URLs of servers users typed
into API Testing, and it was caught by reading the SDK's defaults rather than
by anything in this code.

It is now enforced in the pipe. Every property crossing either sink passes
through `TelemetryScrub` (ADBKit, pure, 13 tests).

| rejected | example |
|---|---|
| absolute / relative / home paths | `/Users/x/app.apk`, `~/Library/…`, `./rel` |
| URLs of any scheme | `https://api.example.com/v1?token=…` |
| email addresses | `someone@example.com` |
| IPv4 and IPv6 literals | `10.0.1.42`, `fe80::1` |
| reverse-DNS shapes (package/bundle ids) | `com.example.myapp` |
| **anything containing whitespace** | `adb shell pm clear com.foo` |
| percent-encoding, quotes, non-ASCII | `%2Fsecret`, `"…"`, `日本語` |
| anything over 512 characters | prose |
| any type that is not a number, bool, string or `[String]` | a stringified object |

A rejected value becomes a visible `<redacted>` marker and the event carries a
`telemetry_redacted` count. Deliberately not silent: a hole in a dashboard gets
asked about, and the answer is always a call site that needs fixing. A
`telemetry_redacted` that starts appearing in PostHog **is a bug report** —
treat it as one.

The whitespace rule is the one that earns its keep. An adb command line clears
every other check: its words are alphanumeric, its package id is only two
components, it has no path separators. Nothing legitimate has a space in it —
feature ids are kebab-case, `open_features` is comma-joined, versions are
dotted.

### What the scrubber cannot catch

Stated plainly, because a filter trusted for more than it does is worse than
none:

- **A bare adb serial** (`emulator-5554`) is shaped exactly like a feature id.
  No value-level filter can separate them. This stays a call-site rule.
- **A bare hostname** without a dot (`localhost`, `buildserver`) likewise.
- **A three-part numeric string** that happens to be sensitive would pass as a
  version.

Today nothing passes any of those: `trackDeviceConnected` sends two booleans
and no identity, and every other string is a feature id, a fixed label, or a
version. The rule for new call sites is unchanged — pass numbers and feature
ids, never a value that came from a device or from something the user typed.

### Other privacy posture

- `sendDefaultPii = false` on Sentry.
- `enableCaptureFailedRequests = false` — this is the setting that was
  shipping user-authored API Testing URLs. Do not turn it back on.
- PostHog `personProfiles = .identifiedOnly`, error autocapture off (Sentry
  owns crashes).
- `AppLog` accepts `Area` (a closed enum) plus `[String: Int]`, so a log line
  cannot carry a string at all. It is rate-limited to 5 lines per area per
  minute; the suppressed count rides out on the next admitted line.
- Breadcrumbs take a free-form message and are **not** scrubbed — they are
  developer-authored strings at fixed call sites, never interpolated with user
  input. Keep it that way.

---

## 2. What is collected

### Super-properties (on every event)

`app_version`, `app_build`, `macos_version`, `mac_arch`, `role`,
`active_feature`, `open_features`, `open_feature_count`, `app_active`, plus
PostHog's own `$geoip_*` (city-level, from the request IP — not stored by us),
`$device_model`, `$screen_*`, `$locale`.

### Events

| event | when | carries |
|---|---|---|
| `app_launched` | once per launch | launch count |
| `feature_used` | a feature is opened or run | feature id, kind |
| `feature_foreground` | the foreground feature changes | prior feature, dwell seconds |
| `device_connected` | a device appears | `is_emulator`, `is_wireless` — no identity |
| `role_selected` | role picked or changed | role, `is_change` |
| `feature_perf` | a per-feature resource window closes | feature, seconds, samples, `avg_cpu`, `peak_cpu`, `avg_mem_mb`, `peak_mem_mb` |
| `app_health` | every 5 min, when there is something to say | the full state block below |
| `app_hang` | Sentry detects a ≥2 s main-thread hang | the full state block below |
| `app_perf_incident` | sustained CPU or memory overuse | the full state block, plus `metric`, `value`, `limit` |
| `app_perf_recovered` | usage falls back | metric, peak, duration |
| `reactotron_timeline_usage` | Reactotron timeline interaction | usage counts |

### The state block

`app_health`, `app_hang` and `app_perf_incident` now share one builder, so all
three answer the same questions. Previously each carried a different subset and
"was memory also high when CPU tripped?" meant joining events by hour.

**Memory**
`memory_mb` (physical footprint, `ri_phys_footprint`), `memory_growth_pct`
(against the session's first sample), `memory_avg_mb`, `memory_peak_mb`,
`memory_delta_mb` (the window's climb — a leak in progress versus a plateau).

**CPU** — new; nothing collected app-wide CPU before.
`cpu_avg`, `cpu_peak`, `usage_samples`.

**Main thread**
`stall_worst_ms`, `stall_median_ms`, `stall_percent`, `stall_samples`,
`stall_discarded`.

**Memory ledger** — new. Resident estimates per retainer, and the subtraction.
`mem_known_mb`, `mem_unknown_mb`, `mem_known_pct`, `mem_retainers`,
`mem_retainers_watched`, and per owner `mem_rt_mb`, `mem_js_mb`,
`mem_shot_mb`, … with matching `_items`.

**Feed wire bytes** — unchanged meaning, kept for series continuity.
`feeds`, `feeds_watched`, `feed_rows`, `feed_mb`, `rt_rows`, `rt_mb`,
`js_rows`, `js_mb`. These are *wire* bytes (frames as they came off the
socket). The `mem_*` keys are *resident* estimates. Do not add them together.

**Workload census** — new. What was running, as opposed to what was on screen.
`work_mirrors`, `work_shells`, `work_devices`, `work_windows`, `work_tabs`,
`work_session_seconds`.

---

## 3. Alerts

`ResourceWatchdog` (ADBKit, pure) samples every 5 s and fires
`app_perf_incident` plus a Sentry warning on sustained overuse.

| metric | limit | notes |
|---|---|---|
| CPU | 200% | 100% = one busy core |
| CPU, with a mirror or recording open | 450% | raised, never waived — an unbounded waiver hid the v3.1.0 mirror leak for hours |
| memory | 1500 MB | physical footprint |

Debounce: 3 consecutive over-limit samples (15 s). Recovery at 80% of the
limit. Repeat alerts for the same metric are suppressed for 30 min.

The Sentry issue is fingerprinted per `(metric, active feature)` and its title
now names the workload — *"High memory: 1.5 GB while reactotron is active — 3
mirrors, 5 shells, 14 tabs"* — because the feature name alone was misleading:
every tab stays mounted, so `active_feature` is what the user was **looking
at**, not what was working.

The health beat also fires on a footprint over **512 MB** even when nothing
else is wrong. It used to be gated on feed rows, which meant the one session
that most needed explaining — heavy, but held by something that is not a feed —
sent nothing at all.

---

## 4. What this now answers that it could not

- **Which subsystem holds the memory?** `mem_*` per owner, and
  `mem_unknown_mb` when the answer is "none of the ones we measure".
- **What does the app normally cost?** `cpu_avg` / `memory_avg_mb`. A 102% peak
  means one thing on a process that idles at 3% and another on one that sits
  at 40.
- **Is this a leak or a plateau?** `memory_delta_mb` across the window.
- **What was the user doing?** the `work_*` census.
- **Was the other metric also bad?** every alert carries both.
- **How long was the hang, really?** `stall_worst_ms`, now with system sleep
  excluded (see below).

## 5. What is still unmeasured — the named gaps

Be honest about these rather than reading a low `mem_known_pct` as a mystery.

**Retainers with no reporter yet.** The ledger has owner slots for `logcat`,
`ioslog`, `crashes` and `decompile` but nothing reports into them. Wired today:
Reactotron, JS Console, the screenshot editor. So `mem_unknown_mb` currently
includes those four plus everything below.

**Mirror sessions.** A scrcpy session's decoded frames live in an
`AVSampleBufferDisplayLayer` the app never owns a buffer for, so it cannot size
itself. `work_mirrors` says how many are running, which is the actionable half.

**The SwiftUI view tree.** Every tab stays mounted; with 14 tabs open the
retained layout and text storage is real and unmeasurable from inside.

**WebKit.** CodeMirror webviews (APK Studio, the code editor) run in their own
process — out of `ri_phys_footprint` entirely, so they do not even appear in
`memory_mb`.

**Two census fields that were deliberately dropped:** live screen recordings
and live feed connections. Neither has an app-wide registry to ask, and a field
that is always zero reads as "none were running" rather than "nobody counted".
They belong in `WorkloadCensus` once those registries exist.

**Per-feature memory is still per *active* feature.** `feature_perf` attributes
whole-process memory to whatever was in the foreground. That is why
`peak_mem_mb` of 1677 MB on `reactotron` should not be read as "reactotron used
1.6 GB" — it means "the process was at 1.6 GB while reactotron was on screen".
The ledger is the number to use instead.

---

## 6. Known-good and known-bad readings

**`stall_worst_ms` before this pass was wrong.** `MainThreadLoad` measured on a
`ContinuousClock`, which keeps counting while the Mac is asleep, so a closed
lid read as a multi-minute main-thread stall: 164 s, 298 s, 407 s and 577 s
were all reported in three days, all with the app backgrounded. When the
suspension was the only stalled sample in a window it was the median too.
Anything from **3.12.1 and earlier is untrustworthy above about 30 s**.

It now measures on a `SuspendingClock` (excludes system sleep by construction)
and discards samples past a 60 s ceiling for App Nap, which no clock separates
from work. The ceiling sits above the longest stall this app can really produce
— a synchronous adb call at its 30 s timeout. Discards are counted and shipped
as `stall_discarded`, so a ceiling set too low announces itself as a climbing
count rather than by quietly swallowing real hangs.

**`feed_mb` is wire, not resident.** The `FeedMemoryBudget` reasoning is that a
decoded frame costs about 8× its wire size. That multiplier is an estimate and
has never been validated against a real footprint — validating it is exactly
what `mem_known_pct` is for. If it pins at 100% repeatedly the multiplier is
too generous; if `mem_unknown_mb` stays near the whole footprint, the feeds
were never the problem.

**A hang's Sentry `durationMs` is meaningless.** Sentry fills it in from
`appHangTimeoutInterval`, so every report reads "at least 2000 ms". Use
`stall_worst_ms`.

---

## 7. Rules for adding telemetry

1. Logic and decisions in ADBKit, pure and tested. The App layer samples and
   ships.
2. Numbers and feature ids only. Never a value that came from a device or from
   something the user typed — the scrubber is a backstop, not permission.
3. A new retainer of any size gets a `MemoryLedger.Owner` case and a reporter,
   or `mem_unknown_mb` silently absorbs it.
4. A new field that cannot be populated yet does not ship. An always-zero
   count reads as a fact.
5. Event volume matters — both sinks are on free plans. Prefer riding an
   existing event (a diagnostic context, the state block) over a new one.
