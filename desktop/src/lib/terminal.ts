/**
 * The terminal's pure parts: the pane layout inside a tab, and the byte
 * encoding the pty topic rides on.
 *
 * A direct port of ADBKit's `TerminalSplitTree`, node for node, so a split
 * behaves the same on all three platforms — including the part that is easy to
 * get subtly different: splitting along the axis of the enclosing split adds an
 * *equal sibling* (thirds, quarters) rather than halving one pane, and closing a
 * pane hands its space back to its siblings.
 */


/** `vertical` is a vertical divider — panes side by side. */
export type SplitDirection = "vertical" | "horizontal"

export type SplitNode =
  | { kind: "pane"; id: string }
  | { kind: "split"; direction: SplitDirection; children: SplitNode[] }

export function singlePane(id: string): SplitNode {
  return { kind: "pane", id }
}

/** Every pane id in layout order: depth-first, first to last per split. */
export function paneIds(node: SplitNode): string[] {
  if (node.kind === "pane") return [node.id]
  return node.children.flatMap(paneIds)
}

export function containsPane(node: SplitNode, id: string): boolean {
  return paneIds(node).includes(id)
}

/**
 * The subtree's first pane, which is the stable React key for a split's child.
 *
 * Positional identity goes stale the moment a sibling closes: the panes after it
 * shift slots, and a `key` on the index would hand an existing slot a different
 * pane — React reuses the DOM node, and the shell that was drawing there keeps
 * drawing into a pane that now belongs to something else.
 */
export function firstPaneId(node: SplitNode): string | null {
  if (node.kind === "pane") return node.id
  for (const child of node.children) {
    const found = firstPaneId(child)
    if (found !== null) return found
  }
  return null
}

/**
 * Divides `pane`'s space with `newPane`, which lands after it — to its right for
 * `vertical`, below it for `horizontal`.
 *
 * Returns the tree unchanged when `pane` is unknown or `newPane` already exists,
 * rather than inventing a second home for one shell.
 */
export function splitPane(
  root: SplitNode,
  pane: string,
  direction: SplitDirection,
  newPane: string,
): SplitNode {
  if (!containsPane(root, pane) || containsPane(root, newPane)) return root
  return splitting(root, pane, direction, newPane)
}

function splitting(
  node: SplitNode,
  pane: string,
  direction: SplitDirection,
  newPane: string,
): SplitNode {
  if (node.kind === "pane") {
    if (node.id !== pane) return node
    return { kind: "split", direction, children: [singlePane(pane), singlePane(newPane)] }
  }
  const index = node.children.findIndex(
    (child) => child.kind === "pane" && child.id === pane,
  )
  // A direct child of a same-direction split gets an equal sibling, not a
  // nested halving — which is what keeps repeated splits evenly sized.
  if (node.direction === direction && index >= 0) {
    const children = [...node.children]
    children.splice(index + 1, 0, singlePane(newPane))
    return { kind: "split", direction: node.direction, children }
  }
  return {
    kind: "split",
    direction: node.direction,
    children: node.children.map((child) => splitting(child, pane, direction, newPane)),
  }
}

/**
 * Removes a pane; its siblings absorb the space. Null once the last pane goes —
 * the owning tab is done.
 */
export function removePane(root: SplitNode, pane: string): SplitNode | null {
  if (!containsPane(root, pane)) return root
  return removing(root, pane)
}

function removing(node: SplitNode, pane: string): SplitNode | null {
  if (node.kind === "pane") return node.id === pane ? null : node
  const kept: SplitNode[] = []
  for (const child of node.children) {
    const reduced = removing(child, pane)
    if (reduced !== null) kept.push(reduced)
  }
  if (kept.length === 0) return null
  // A split left with one child collapses into it.
  if (kept.length === 1) return kept[0] ?? null
  // Which can surface a same-direction split — flatten it so its panes go back
  // to being equal siblings instead of one of them being half the size.
  const flattened: SplitNode[] = []
  for (const child of kept) {
    if (child.kind === "split" && child.direction === node.direction) {
      flattened.push(...child.children)
    } else {
      flattened.push(child)
    }
  }
  return { kind: "split", direction: node.direction, children: flattened }
}

/**
 * Where focus lands after `pane` closes: whichever pane slides into its slot in
 * layout order, or the previous one when it was last.
 */
export function neighborPane(root: SplitNode, pane: string): string | null {
  const flat = paneIds(root)
  const index = flat.indexOf(pane)
  if (index < 0) return null
  const remaining = flat.filter((id) => id !== pane)
  if (remaining.length === 0) return null
  return remaining[Math.min(index, remaining.length - 1)] ?? null
}

// MARK: - the wire's bytes

/**
 * Keystrokes as the `write` op wants them.
 *
 * xterm hands us a JS string; the pty wants bytes. Encoding to UTF-8 first
 * matters for anything outside Latin-1 — `btoa` throws on a code unit above
 * 255, so a pasted emoji would otherwise take the terminal down rather than
 * being typed.
 */
export function encodeInput(text: string): string {
  return encodeBytes(new TextEncoder().encode(text))
}

/**
 * xterm's `onBinary` payload, which is already a byte-per-code-unit string
 * rather than text — mouse reports arrive this way, and re-encoding one as UTF-8
 * would corrupt every coordinate above 127.
 */
export function encodeBinary(raw: string): string {
  const bytes = new Uint8Array(raw.length)
  for (let index = 0; index < raw.length; index += 1) {
    // `charCodeAt`, not `codePointAt`: this string is one byte per code unit
    // already, and a code point would fuse a surrogate pair into a number no
    // byte can hold — which is the corruption this function exists to avoid.
    // oxlint-disable-next-line unicorn/prefer-code-point
    bytes[index] = raw.charCodeAt(index) & 0xff
  }
  return encodeBytes(bytes)
}

/**
 * Base64 without spreading into `String.fromCharCode(...bytes)`, which throws
 * on a large paste: the argument list is the limit, and a few tens of thousands
 * of characters is enough to hit it.
 */
function encodeBytes(bytes: Uint8Array): string {
  let binary = ""
  // `fromCharCode`, not `fromCodePoint`: `btoa` wants one byte per code unit,
  // which is what this builds. They agree for 0…255 and diverge above it, so
  // the "better Unicode support" the rule offers is the wrong behaviour here.
  // oxlint-disable-next-line unicorn/prefer-code-point
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
}

/**
 * A chunk of shell output, back to bytes.
 *
 * Handed to xterm as bytes rather than a decoded string on purpose: a pty read
 * ends wherever the buffer filled, so a chunk can stop mid-character, and
 * xterm's own decoder is the thing that carries the remainder into the next
 * write. Decoding here would substitute U+FFFD for it.
 */
export function decodeChunk(base64: string): Uint8Array {
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) {
    // One byte per code unit, which is exactly what `atob` produced — see
    // `encodeBytes` for why a code point would be wrong.
    // oxlint-disable-next-line unicorn/prefer-code-point
    bytes[index] = binary.charCodeAt(index)
  }
  return bytes
}
