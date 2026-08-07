import { describe, expect, it } from "vitest"
import raw from "@/lib/__fixtures__/features.json"
import { connectDeviceHint, hintedFeatureIDs } from "@/lib/hints"
import type { FeatureSummary } from "@/lib/wire"

const features = (raw as unknown as { features: FeatureSummary[] }).features

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
    // The ported panes are exactly the ones that can currently show the empty
    // state, so each has to have been considered rather than inheriting the
    // fallback by accident.
    const ported = [
      "logcat",
      "apps",
      "file-explorer",
      "device-info",
      "crash-catcher",
      "performance",
      "root-status",
      "dev-settings",
      "system-restrictions",
    ]
    for (const id of ported) expect(hintedFeatureIDs()).toContain(id)
  })
})
