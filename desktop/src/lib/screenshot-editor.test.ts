import { describe, expect, it } from "vitest"
import {
  commitDraft,
  committedText,
  DEFAULT_SETTINGS,
  extendDraft,
  MIN_DRAG,
  pushUndo,
  showsRedactControls,
  startDraft,
  suggestedName,
  trashAction,
  zoomIn,
  zoomOut,
  type Snapshot,
} from "@/lib/screenshot-editor"
import { annotation, MAX_UNDO, type Annotation } from "@/lib/screenshot-markup"

function snapshot(n: number): Snapshot {
  return {
    image: n as unknown as ImageBitmap,
    size: { width: 100, height: 200 },
    annotations: [],
  }
}

describe("pushUndo", () => {
  it("keeps the history in order", () => {
    const stack = pushUndo(pushUndo([], snapshot(1)), snapshot(2))
    expect(stack.map((s) => s.image)).toEqual([1, 2])
  })

  it("drops the oldest once it is full", () => {
    let stack: Snapshot[] = []
    for (let i = 0; i < MAX_UNDO + 5; i += 1) stack = pushUndo(stack, snapshot(i))
    expect(stack).toHaveLength(MAX_UNDO)
    // The five oldest are gone, the newest is on top.
    expect(stack[0]?.image).toBe(5)
    expect(stack.at(-1)?.image).toBe(MAX_UNDO + 4)
  })
})

describe("zoom", () => {
  it("steps by a quarter each way", () => {
    expect(zoomIn(1)).toBeCloseTo(1.25, 8)
    expect(zoomOut(1)).toBeCloseTo(0.8, 8)
  })

  it("stops at the ends rather than running away", () => {
    let zoom = 1
    for (let i = 0; i < 50; i += 1) zoom = zoomIn(zoom)
    expect(zoom).toBe(8)
    for (let i = 0; i < 100; i += 1) zoom = zoomOut(zoom)
    expect(zoom).toBe(0.2)
  })
})

describe("startDraft", () => {
  it("gives a drag shape two points so the first move has something to move", () => {
    const draft = startDraft({ ...DEFAULT_SETTINGS, tool: "rectangle" }, { x: 0.2, y: 0.3 })
    expect(draft.points).toEqual([{ x: 0.2, y: 0.3 }, { x: 0.2, y: 0.3 }])
  })

  it("gives a freehand stroke one", () => {
    const draft = startDraft({ ...DEFAULT_SETTINGS, tool: "pen" }, { x: 0.2, y: 0.3 })
    expect(draft.points).toEqual([{ x: 0.2, y: 0.3 }])
  })

  it("carries the current settings onto the new annotation", () => {
    const draft = startDraft(
      { ...DEFAULT_SETTINGS, tool: "redact", color: "#00ff00", width: 12, redactStyle: "solid", fillOpacity: 0.5 },
      { x: 0, y: 0 },
    )
    expect(draft).toMatchObject({ color: "#00ff00", width: 12, redactStyle: "solid", fillOpacity: 0.5 })
  })
})

describe("extendDraft", () => {
  it("moves the far end of a drag shape rather than adding points", () => {
    const draft = startDraft({ ...DEFAULT_SETTINGS, tool: "line" }, { x: 0.1, y: 0.1 })
    const moved = extendDraft(extendDraft(draft, { x: 0.4, y: 0.4 }), { x: 0.6, y: 0.2 })
    expect(moved.points).toEqual([{ x: 0.1, y: 0.1 }, { x: 0.6, y: 0.2 }])
  })

  it("appends to a freehand stroke", () => {
    const draft = startDraft({ ...DEFAULT_SETTINGS, tool: "pen" }, { x: 0.1, y: 0.1 })
    const moved = extendDraft(extendDraft(draft, { x: 0.2, y: 0.2 }), { x: 0.3, y: 0.3 })
    expect(moved.points).toHaveLength(3)
  })
})

describe("commitDraft", () => {
  it("throws away a drag that never really moved", () => {
    const draft = startDraft({ ...DEFAULT_SETTINGS, tool: "rectangle" }, { x: 0.5, y: 0.5 })
    const barely = extendDraft(draft, { x: 0.5 + MIN_DRAG / 2, y: 0.5 })
    expect(commitDraft(barely)).toBeNull()
  })

  it("keeps a drag that did", () => {
    const draft = startDraft({ ...DEFAULT_SETTINGS, tool: "rectangle" }, { x: 0.5, y: 0.5 })
    const real = extendDraft(draft, { x: 0.7, y: 0.6 })
    expect(commitDraft(real)).not.toBeNull()
  })

  it("keeps a single-tap pen mark, which is a dot and not a mistake", () => {
    const draft = startDraft({ ...DEFAULT_SETTINGS, tool: "pen" }, { x: 0.5, y: 0.5 })
    expect(commitDraft(draft)).not.toBeNull()
  })
})

describe("committedText", () => {
  it("trims the label", () => {
    const made = committedText(DEFAULT_SETTINGS, { x: 0.1, y: 0.1 }, "  hello  ")
    expect(made?.text).toBe("hello")
  })

  it("is nothing for an empty or blank label", () => {
    expect(committedText(DEFAULT_SETTINGS, { x: 0, y: 0 }, "")).toBeNull()
    expect(committedText(DEFAULT_SETTINGS, { x: 0, y: 0 }, "   ")).toBeNull()
  })
})

describe("trashAction", () => {
  const one: Annotation[] = [annotation({ tool: "pen", points: [{ x: 0, y: 0 }] })]

  it("clears everything when nothing is selected", () => {
    expect(trashAction(false, null, one)).toEqual({
      action: "clear",
      label: "Clear all markup",
      enabled: true,
    })
  })

  it("is disabled with nothing to clear", () => {
    expect(trashAction(false, null, []).enabled).toBe(false)
  })

  it("deletes just the selection while one is picked", () => {
    expect(trashAction(true, "abc", one)).toEqual({
      action: "delete",
      label: "Delete selection",
      enabled: true,
    })
  })

  it("is disabled in select mode with nothing picked", () => {
    // Not "clear all": the Mac disables it, because the button's meaning in
    // select mode is the selection, and clearing everything from there would
    // be a different verb behind the same icon.
    expect(trashAction(true, null, one).enabled).toBe(false)
  })
})

describe("showsRedactControls", () => {
  it("shows them while the redact tool is chosen", () => {
    expect(showsRedactControls({ ...DEFAULT_SETTINGS, tool: "redact" }, false, null)).toBe(true)
    expect(showsRedactControls({ ...DEFAULT_SETTINGS, tool: "pen" }, false, null)).toBe(false)
  })

  it("follows the selection in select mode, not the tool", () => {
    const redaction = annotation({ tool: "redact", points: [] })
    const stroke = annotation({ tool: "pen", points: [] })
    expect(showsRedactControls({ ...DEFAULT_SETTINGS, tool: "pen" }, true, redaction)).toBe(true)
    expect(showsRedactControls({ ...DEFAULT_SETTINGS, tool: "redact" }, true, stroke)).toBe(false)
    expect(showsRedactControls({ ...DEFAULT_SETTINGS, tool: "redact" }, true, null)).toBe(false)
  })
})

describe("suggestedName", () => {
  it("matches ScreenCaptureService.stamp()'s format", () => {
    // Local time, zero-padded, exactly as the Mac writes it — a folder holding
    // captures from both apps should sort as one set.
    const name = suggestedName(new Date(2026, 8, 19, 2, 4, 5))
    expect(name).toBe("screenshot_2026-09-19_02-04-05.png")
  })
})
