import { describe, expect, it } from "vitest"

import {
  toolAction,
  toolName,
  toolPurpose,
  toolSizeLabel,
  toolVersionLabel,
  TOOL_DESCRIPTIONS,
  type ManagedToolEntry,
} from "@/lib/managed-tools"

function entry(over: Partial<ManagedToolEntry> = {}): ManagedToolEntry {
  return {
    id: "jadx",
    installed: true,
    version: "v1.5.6",
    pinnedVersion: "v1.5.6",
    sizeBytes: 12_582_912,
    ...over,
  }
}

describe("toolAction", () => {
  /**
   * Three states rather than two. An installed tool whose pin has moved is
   * neither "install" nor "nothing to do", and offering only Remove would hide
   * an upgrade the app update shipped.
   */
  it("tells install, upgrade and current apart", () => {
    expect(toolAction(entry({ installed: false, version: null }))).toBe("install")
    expect(toolAction(entry({ version: "v1.5.0", pinnedVersion: "v1.5.6" }))).toBe("upgrade")
    expect(toolAction(entry())).toBe("installed")
  })

  /**
   * An installed tool with no recorded version cannot be compared, so it is
   * current rather than perpetually upgradable — which would make Upgrade a
   * button that never stops asking.
   */
  it("treats an installed tool with no version as current", () => {
    expect(toolAction(entry({ version: null }))).toBe("installed")
  })
})

describe("toolVersionLabel", () => {
  it("names what is on disk, and the newer pin beside it", () => {
    expect(toolVersionLabel(entry())).toBe("v1.5.6")
    expect(toolVersionLabel(entry({ version: "v1.5.0", pinnedVersion: "v1.5.6" }))).toBe(
      "v1.5.0 · v1.5.6 available",
    )
  })

  it("offers the pin when nothing is installed", () => {
    expect(toolVersionLabel(entry({ installed: false, version: null }))).toBe(
      "Not installed · v1.5.6 available",
    )
  })
})

describe("toolSizeLabel", () => {
  it("steps from bytes to megabytes, and says nothing for nothing", () => {
    expect(toolSizeLabel(0)).toBe("—")
    expect(toolSizeLabel(512)).toBe("512 B")
    expect(toolSizeLabel(2048)).toBe("2.0 KB")
    expect(toolSizeLabel(12_582_912)).toBe("12.0 MB")
  })
})

describe("the description table", () => {
  /**
   * The guard `icons.ts` and `sidebar.ts` carry: a tool added to the daemon's
   * catalogue must be described here, or it appears in Settings as a bare slug
   * with no idea what it is for. The ids are `ManagedTool`'s raw values.
   */
  it("describes every tool the daemon's catalogue can serve", () => {
    const served = [
      "jadx",
      "apktool",
      "uber-apk-signer",
      "frida-server",
      "frida-gadget",
      "temurin-jre",
      "bundletool",
      "ffmpeg",
    ]
    for (const id of served) {
      expect(TOOL_DESCRIPTIONS[id], `${id} has no description`).toBeDefined()
      expect(toolName(id)).not.toBe("")
      expect(toolPurpose(id)).not.toBe("")
    }
  })

  /** An id nobody described still renders, as itself rather than as blank. */
  it("falls back to the id rather than to nothing", () => {
    expect(toolName("some-new-tool")).toBe("some-new-tool")
    expect(toolPurpose("some-new-tool")).toBe("")
  })
})
