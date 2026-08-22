import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"
import raw from "@/lib/__fixtures__/features.json"
import { connectDeviceHint, hintedFeatureIDs } from "@/lib/hints"
import type { FeatureSummary } from "@/lib/wire"

const features = (raw as unknown as { features: FeatureSummary[] }).features

/**
 * The panes that take a device, read out of the router that decides it.
 *
 * A source read rather than a second list: the switch in `FeaturePane` *is* the
 * answer to which screens exist, and anything restating it is something to keep
 * in agreement.
 *
 * Taking a device is the point, not merely having a pane: `emulators` has one
 * and deliberately takes none — launching an emulator is what you do when
 * nothing is connected — so it can never show this empty state and needs no
 * line for it.
 */
function deviceScopedPaneIDs(): string[] {
  const router = readFileSync(new URL("../components/FeaturePane.tsx", import.meta.url), "utf8")
  // Split at each `case "`, so a block is exactly that case's body. The last
  // one runs on into `default:` and the helpers below it, which is why it is
  // cut there — the fallback passes a device and would claim every trailing
  // case does too.
  return router
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
})
