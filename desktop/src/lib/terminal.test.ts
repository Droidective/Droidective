import { describe, expect, it } from "vitest"
import {
  containsPane,
  decodeChunk,
  encodeBinary,
  encodeInput,
  firstPaneId,
  neighborPane,
  paneIds,
  removePane,
  singlePane,
  splitPane,
  type SplitNode,
} from "@/lib/terminal"

/** A split's children, or none — so an assertion reads as a count, not a guard. */
function children(node: SplitNode | null): SplitNode[] {
  return node !== null && node.kind === "split" ? node.children : []
}

/**
 * The same cases ADBKit's `TerminalSplitTreeTests` covers, because the whole
 * point of porting the model is that a split behaves identically on all three
 * platforms. A divergence here is a difference someone has to relearn.
 */
describe("the pane layout inside a tab", () => {
  it("starts as one pane", () => {
    const tree = singlePane("a")
    expect(paneIds(tree)).toEqual(["a"])
    expect(containsPane(tree, "a")).toBe(true)
    expect(containsPane(tree, "b")).toBe(false)
  })

  it("puts the new pane after the one that was split", () => {
    const tree = splitPane(singlePane("a"), "a", "vertical", "b")
    expect(paneIds(tree)).toEqual(["a", "b"])
  })

  it("adds an equal sibling when splitting along the enclosing axis", () => {
    // The behaviour that makes repeated ⌘D give thirds rather than a half, a
    // quarter and a quarter.
    let tree = splitPane(singlePane("a"), "a", "vertical", "b")
    tree = splitPane(tree, "b", "vertical", "c")
    expect(paneIds(tree)).toEqual(["a", "b", "c"])
    expect(children(tree)).toHaveLength(3)
  })

  it("nests when splitting across the enclosing axis", () => {
    let tree = splitPane(singlePane("a"), "a", "vertical", "b")
    tree = splitPane(tree, "b", "horizontal", "c")
    expect(paneIds(tree)).toEqual(["a", "b", "c"])
    // Two children still: `b` became a stacked pair inside the right half.
    expect(children(tree)).toHaveLength(2)
  })

  it("refuses to give one pane two homes", () => {
    const tree = splitPane(singlePane("a"), "a", "vertical", "b")
    expect(splitPane(tree, "a", "vertical", "b")).toBe(tree)
    expect(splitPane(tree, "nobody", "vertical", "c")).toBe(tree)
  })

  it("collapses a split left with one child", () => {
    const tree = splitPane(singlePane("a"), "a", "vertical", "b")
    const left = removePane(tree, "b")
    expect(left).toEqual(singlePane("a"))
  })

  it("flattens a same-direction split surfaced by a collapse", () => {
    // Without the flatten, `a` and the pair that was `b` end up unequal: the
    // survivors are siblings in name but not in size.
    let tree = splitPane(singlePane("a"), "a", "vertical", "b")
    tree = splitPane(tree, "b", "horizontal", "c")
    tree = splitPane(tree, "c", "horizontal", "d")
    const left = removePane(tree, "a")
    expect(left).not.toBeNull()
    expect(left?.kind === "split" && left.direction).toBe("horizontal")
    expect(children(left)).toHaveLength(3)
  })

  it("empties when the last pane goes", () => {
    expect(removePane(singlePane("a"), "a")).toBeNull()
  })

  it("leaves a tree alone when asked to remove a pane it does not have", () => {
    const tree = singlePane("a")
    expect(removePane(tree, "b")).toBe(tree)
  })

  it("moves focus to whatever slides into the closing pane's slot", () => {
    let tree = splitPane(singlePane("a"), "a", "vertical", "b")
    tree = splitPane(tree, "b", "vertical", "c")
    expect(neighborPane(tree, "b")).toBe("c")
    // Last one closing goes backwards; there is nothing after it.
    expect(neighborPane(tree, "c")).toBe("b")
    expect(neighborPane(singlePane("a"), "a")).toBeNull()
  })

  it("names a subtree by its first pane, so a React key survives a close", () => {
    const nested: SplitNode = {
      kind: "split",
      direction: "vertical",
      children: [
        singlePane("a"),
        { kind: "split", direction: "horizontal", children: [singlePane("b"), singlePane("c")] },
      ],
    }
    expect(firstPaneId(nested)).toBe("a")
    expect(nested.children[1] && firstPaneId(nested.children[1])).toBe("b")
  })
})

/**
 * Byte comparisons go through a spread.
 *
 * `toEqual` on two `Uint8Array`s compares their prototypes as well as their
 * contents, and under jsdom the one `TextEncoder` returns comes from a
 * different realm than the one `decodeChunk` builds — identical bytes, and
 * vitest reports "no visual difference" while failing. Spreading asks the
 * question the test actually means.
 */
function bytes(value: Uint8Array): number[] {
  return [...value]
}

describe("the bytes on the wire", () => {
  it("round-trips ASCII", () => {
    expect(bytes(decodeChunk(encodeInput("ls -la\n")))).toEqual(
      bytes(new TextEncoder().encode("ls -la\n")),
    )
  })

  it("carries a control code, which is why the field is not plain text", () => {
    // Ctrl-C, as an escape rather than a literal ETX byte in the source: the
    // most important key a terminal has to deliver should not be invisible in
    // the test that proves it arrives.
    expect(bytes(decodeChunk(encodeInput("\u0003")))).toEqual([0x03])
    // Escape, tab, backspace and carriage return, none of which a JSON string
    // could hold either.
    expect([...decodeChunk(encodeInput("\u001B\t\b\r"))]).toEqual([0x1b, 0x09, 0x08, 0x0d])
  })

  it("encodes beyond Latin-1 rather than throwing", () => {
    // `btoa` throws on a code unit above 255, so a pasted emoji would take the
    // terminal down instead of being typed.
    const emoji = "🎉"
    expect(bytes(decodeChunk(encodeInput(emoji)))).toEqual(bytes(new TextEncoder().encode(emoji)))
    expect(bytes(decodeChunk(encodeInput("héllo")))).toEqual(
      bytes(new TextEncoder().encode("héllo")),
    )
  })

  it("survives a paste far bigger than an argument list", () => {
    // `String.fromCharCode(...bytes)` throws around here; the loop does not.
    const huge = "x".repeat(200_000)
    expect(decodeChunk(encodeInput(huge)).length).toBe(200_000)
  })

  it("treats onBinary's payload as bytes, not as text", () => {
    // A mouse report's coordinates live above 127 and are already one byte per
    // code unit; re-encoding as UTF-8 would turn each into two.
    // ESC [ M, then a button byte and two coordinates past 127. Built from
    // codes rather than written as a literal so what is asserted is visible:
    // these are bytes, not characters.
    // oxlint-disable-next-line unicorn/prefer-code-point
    const report = String.fromCharCode(0x1b, 0x5b, 0x4d, 0x20, 0xc8, 0xc9)
    expect([...decodeChunk(encodeBinary(report))]).toEqual([
      0x1b, 0x5b, 0x4d, 0x20, 0xc8, 0xc9,
    ])
    // The distinction is real: as text those last two become four bytes.
    expect(decodeChunk(encodeInput(report)).length).toBe(report.length + 2)
  })

  it("hands back the exact bytes of a chunk that split a character", () => {
    // The pty read that ends mid-character. Both halves decode to the bytes
    // they were, and xterm's own decoder joins them.
    const euro = new TextEncoder().encode("€")
    // oxlint-disable-next-line unicorn/prefer-code-point
    const head = encodeBinary(String.fromCharCode(euro[0] ?? 0, euro[1] ?? 0))
    // oxlint-disable-next-line unicorn/prefer-code-point
    const tail = encodeBinary(String.fromCharCode(euro[2] ?? 0))
    expect([...decodeChunk(head), ...decodeChunk(tail)]).toEqual([...euro])
  })

  it("handles an empty chunk", () => {
    expect(decodeChunk(encodeInput(""))).toEqual(new Uint8Array())
  })
})
