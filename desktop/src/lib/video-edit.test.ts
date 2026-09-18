import { describe, expect, it } from "vitest"
import {
  COMPRESSIONS,
  FORMATS,
  hasEdits,
  isFullFrame,
  isIdentity,
  MAX_UNDO,
  MIN_TRIM,
  NO_EDITS,
  normalizedRotation,
  outputSeconds,
  pushUndo,
  SPEEDS,
  suggestedName,
  timecode,
  turned,
  wireOptions,
  withTrim,
  type EditState,
} from "@/lib/video-edit"

function edit(over: Partial<EditState> = {}): EditState {
  return { ...NO_EDITS, ...over }
}

describe("the control tables", () => {
  it("offers the Mac's five speeds in its order", () => {
    expect(SPEEDS).toEqual([0.25, 0.5, 1, 1.5, 2])
  })

  it("offers the Mac's five formats and three compressions", () => {
    expect(FORMATS.map((f) => f.value)).toEqual(["mp4", "mov", "mkv", "webm", "gif"])
    expect(COMPRESSIONS.map((c) => c.value)).toEqual(["none", "medium", "high"])
  })
})

describe("normalizedRotation", () => {
  it("wraps in both directions", () => {
    expect(normalizedRotation(0)).toBe(0)
    expect(normalizedRotation(450)).toBe(90)
    expect(normalizedRotation(-90)).toBe(270)
    expect(normalizedRotation(-450)).toBe(270)
  })
})

describe("turned", () => {
  it("steps a quarter each way and comes back round", () => {
    let state = edit()
    for (let i = 0; i < 4; i += 1) state = turned(state, true)
    expect(state.rotationDegrees).toBe(0)
    expect(turned(edit(), false).rotationDegrees).toBe(270)
  })
})

describe("isIdentity", () => {
  it("is true for an untouched edit", () => {
    expect(isIdentity(NO_EDITS)).toBe(true)
  })

  it("is true for a crop that covers the whole frame", () => {
    // The Mac treats this as no crop, and it has to: otherwise dragging a crop
    // box to the edges would re-encode a file nobody changed.
    expect(isIdentity(edit({ crop: { x: 0, y: 0, width: 1, height: 1 } }))).toBe(true)
  })

  it.each([
    ["a trim", { trimStart: 1 }],
    ["a rotation", { rotationDegrees: 90 }],
    ["a flip", { flipH: true }],
    ["a real crop", { crop: { x: 0.1, y: 0.1, width: 0.5, height: 0.5 } }],
    ["a speed change", { speed: 2 }],
    ["a mute", { mute: true }],
    ["a downscale", { scaleWidth: 720 }],
    ["compression", { compression: "high" as const }],
  ])("is false for %s", (_label, over) => {
    expect(isIdentity(edit(over))).toBe(false)
  })

  it("ignores the format, which is the container rather than an edit", () => {
    // A format change still re-encodes, but that decision is the caller's:
    // `isIdentity` means "the pixels are untouched", and the Mac pairs it with
    // an extension check before copying.
    expect(isIdentity(edit({ format: "webm" }))).toBe(true)
  })
})

describe("isFullFrame", () => {
  it("allows for rounding", () => {
    expect(isFullFrame({ x: 0.00005, y: 0, width: 0.99995, height: 1 })).toBe(true)
    expect(isFullFrame({ x: 0.01, y: 0, width: 0.99, height: 1 })).toBe(false)
  })
})

describe("hasEdits", () => {
  it("is false for an untouched edit, whatever format is chosen", () => {
    expect(hasEdits(NO_EDITS)).toBe(false)
    expect(hasEdits(edit({ format: "gif" }))).toBe(false)
  })

  it("is true once something is changed", () => {
    expect(hasEdits(edit({ mute: true }))).toBe(true)
  })
})

describe("withTrim", () => {
  it("clears both ends together", () => {
    const cleared = withTrim(edit({ trimStart: 1, trimEnd: 2 }), null, null, 10)
    expect(cleared.trimStart).toBeNull()
    expect(cleared.trimEnd).toBeNull()
  })

  it("keeps the two ends at least a frame apart", () => {
    // A zero-length trim exports an empty file, which reads as a broken export
    // rather than as a mis-drag.
    const tight = withTrim(edit(), 5, 5, 10)
    expect((tight.trimEnd ?? 0) - (tight.trimStart ?? 0)).toBeCloseTo(MIN_TRIM, 6)
  })

  it("pulls a crossed-over drag back into order", () => {
    const crossed = withTrim(edit(), 8, 2, 10)
    expect(crossed.trimStart ?? 0).toBeLessThan(crossed.trimEnd ?? 0)
  })

  it("clamps to the clip", () => {
    const past = withTrim(edit(), -4, 99, 10)
    expect(past.trimStart).toBe(0)
    expect(past.trimEnd).toBe(10)
  })

  it("defaults a missing end to the duration", () => {
    expect(withTrim(edit(), 2, null, 10).trimEnd).toBe(10)
  })
})

describe("outputSeconds", () => {
  it("is the whole clip with no trim and no speed change", () => {
    expect(outputSeconds(NO_EDITS, 12)).toBe(12)
  })

  it("shortens with the trim", () => {
    expect(outputSeconds(edit({ trimStart: 2, trimEnd: 8 }), 12)).toBe(6)
  })

  it("divides by the speed", () => {
    expect(outputSeconds(edit({ speed: 2 }), 12)).toBe(6)
    expect(outputSeconds(edit({ speed: 0.5 }), 12)).toBe(24)
  })

  it("never goes negative", () => {
    expect(outputSeconds(edit({ trimStart: 9, trimEnd: 3 }), 12)).toBe(0)
  })
})

describe("timecode", () => {
  it("reads as m:ss under an hour", () => {
    expect(timecode(0)).toBe("0:00")
    expect(timecode(9)).toBe("0:09")
    expect(timecode(75)).toBe("1:15")
  })

  it("grows an hours field past an hour", () => {
    expect(timecode(3675)).toBe("1:01:15")
  })

  it("floors rather than rounding up past the end", () => {
    expect(timecode(9.99)).toBe("0:09")
  })
})

describe("pushUndo", () => {
  it("drops the oldest once full", () => {
    let stack: EditState[] = []
    for (let i = 0; i < MAX_UNDO + 3; i += 1) stack = pushUndo(stack, edit({ speed: i }))
    expect(stack).toHaveLength(MAX_UNDO)
    expect(stack[0]?.speed).toBe(3)
  })
})

describe("suggestedName", () => {
  it("keeps the source's stem and takes the chosen extension", () => {
    expect(suggestedName("/home/me/Downloads/recording_2026-09-19.mp4", "gif")).toBe(
      "recording_2026-09-19.gif",
    )
  })

  it("handles a Windows path", () => {
    expect(suggestedName("C:\\Users\\me\\clip.mkv", "mp4")).toBe("clip.mp4")
  })

  it("copes with a name that has no extension", () => {
    expect(suggestedName("/tmp/clip", "mp4")).toBe("clip.mp4")
  })
})

describe("wireOptions", () => {
  it("flattens the crop into four fields, or four nulls", () => {
    expect(wireOptions(NO_EDITS)).toMatchObject({
      cropX: null,
      cropY: null,
      cropWidth: null,
      cropHeight: null,
    })
    expect(wireOptions(edit({ crop: { x: 0.1, y: 0.2, width: 0.3, height: 0.4 } }))).toMatchObject({
      cropX: 0.1,
      cropY: 0.2,
      cropWidth: 0.3,
      cropHeight: 0.4,
    })
  })

  it("normalizes the rotation before sending it", () => {
    expect(wireOptions(edit({ rotationDegrees: -90 }))).toMatchObject({ rotationDegrees: 270 })
  })

  it("carries every other field through unchanged", () => {
    const state = edit({
      trimStart: 1,
      trimEnd: 2,
      flipH: true,
      flipV: true,
      speed: 1.5,
      mute: true,
      scaleWidth: 720,
      compression: "medium",
      format: "mov",
    })
    expect(wireOptions(state)).toMatchObject({
      trimStart: 1,
      trimEnd: 2,
      flipH: true,
      flipV: true,
      speed: 1.5,
      mute: true,
      scaleWidth: 720,
      compression: "medium",
      format: "mov",
    })
  })
})
