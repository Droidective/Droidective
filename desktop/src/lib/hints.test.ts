// @vitest-environment node
//
// A source-reading test, so it runs in node rather than the project's default
// jsdom: jsdom rewrites `import.meta.url` to an http URL, and `readFileSync`
// then refuses it ("The URL must be of scheme file"). Nothing here touches a
// DOM, so the override costs nothing.
import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"
import raw from "@/lib/__fixtures__/features.json"
import { connectDeviceHint, hintedFeatureIDs } from "@/lib/hints"
import type { FeatureSummary } from "@/lib/wire"

const features = (raw as unknown as { features: FeatureSummary[] }).features

/**
 * The panes that *require* a device, read out of the router that decides it.
 *
 * A source read rather than a second list: the switch in `FeaturePane` *is* the
 * answer to which screens exist, and anything restating it is something to keep
 * in agreement.
 *
 * Requiring one is the point, not merely having a pane, and not merely being
 * handed a device either. The screens in `hostPane` all run against *this*
 * machine and work with nothing connected — `emulators` because launching one
 * is what you do when nothing is attached, `terminal` because a shell is local,
 * `reactotron` because the relay is a listener here and a device only matters
 * for its reverse tunnel. None of them can reach the connect-a-device empty
 * state, so a line for it would be dead text.
 */
function deviceScopedPaneIDs(): string[] {
  const router = readFileSync(new URL("../components/FeaturePane.tsx", import.meta.url), "utf8")
  // Cut the host-side group off before splitting. `reactotron` is handed a
  // device (`device={device}`) and still belongs outside this list, so the
  // exclusion has to be structural rather than another substring test.
  const deviceScoped = router.split("function hostPane(")[0] ?? router
  // Split at each `case "`, so a block is exactly that case's body. The last
  // one runs on into `default:`, which is why it is cut there — the fallback
  // passes a device and would claim every trailing case does too.
  return deviceScoped
    .split(/\n\s*case "/u)
    .slice(1)
    .map((block) => ({ id: block.slice(0, block.indexOf('"')), body: block.split("default:")[0] }))
    .filter((entry) => entry.body?.includes("device=") === true)
    .map((entry) => entry.id)
}

describe("connectDeviceHint", () => {
  it("uses the Mac's exact line for a feature the table names", () => {
    expect(connectDeviceHint("send-text", "Send Text")).toBe("Connect a device to send text.")
    expect(connectDeviceHint("get-ip", "Get IP")).toBe("Connect a device to copy its IP address.")
  })

  it("derives a specific line from the title for anything else", () => {
    // The fallback is what stops an unlisted feature reading as a generic
    // screen — every one of them still says what it wants a device for.
    expect(connectDeviceHint("brand-new", "Brand New")).toBe("Connect a device to use Brand New.")
  })
})

describe("the hint table", () => {
  it("names no feature that is not in the registry", () => {
    // A renamed id would otherwise leave the old line here, unreachable, while
    // the renamed feature quietly fell back to the generic sentence.
    const known = new Set(features.map((feature) => feature.id))
    for (const id of hintedFeatureIDs()) {
      expect(known, `${id} has a hint but is not a registry feature`).toContain(id)
    }
  })

  it("says something for every screen this app has ported", () => {
    // The ported panes are exactly the ones that can show the empty state, so
    // each has to have been considered rather than inheriting the fallback by
    // accident.
    //
    // Read out of the pane router rather than listed here. As a literal list it
    // went stale the moment the tenth screen landed, and a test that no longer
    // covers what it claims to is worse than no test — the same reason
    // `generate-parity-tracker.py` reads the router too.
    for (const id of deviceScopedPaneIDs()) {
      expect(hintedFeatureIDs(), `${id} has a pane but no empty-state line`).toContain(id)
    }
  })

  it("finds the panes it is meant to be checking", () => {
    // A regex over a source file is only as good as the file's shape. If the
    // router is ever rewritten into something this cannot read, the test above
    // would silently pass over an empty list.
    expect(deviceScopedPaneIDs().length).toBeGreaterThan(15)
    expect(deviceScopedPaneIDs()).toContain("logcat")
  })

  it("leaves the host-side screens out of it", () => {
    // The cut at `hostPane` is doing the work here. Without it `reactotron`
    // reads as device-scoped — it is handed one — and the test above would
    // demand an empty-state line for a screen that cannot show one.
    expect(deviceScopedPaneIDs()).not.toContain("reactotron")
    expect(deviceScopedPaneIDs()).not.toContain("terminal")
    expect(deviceScopedPaneIDs()).not.toContain("emulators")
  })
})
