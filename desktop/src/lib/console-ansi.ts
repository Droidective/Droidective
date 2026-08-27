/**
 * Terminal escape sequences, removed — a port of ADBKit's `ConsoleANSI`.
 *
 * React Native's dev server writes its notices coloured for a terminal, so they
 * arrive over CDP with real escape bytes in them. Rendered as-is they read as
 * `ESC[48;2;…m ESC[1mNOTE: ESC[22mYou are using…`, which is exactly what
 * the console showed before this existed.
 *
 * Byte-wise rather than by regular expression, and matching the Swift exactly:
 * an *unterminated* escape is left alone rather than swallowing the rest of the
 * line, because a lone ESC in real data is data.
 */

const ESCAPE = 0x1b
const BELL = 0x07
const OPEN_BRACKET = 0x5b
const CLOSE_BRACKET = 0x5d
const BACKSLASH = 0x5c

/** Cheap pre-check: most console lines carry no escapes at all. */
function containsEscapes(text: string): boolean {
  return text.includes("\u001B")
}

/**
 * The text without its escape sequences: CSI (`ESC [ … final`), OSC
 * (`ESC ] … BEL` or `ESC ] … ESC \`), and the two-byte C1 forms.
 */
export function stripAnsi(text: string): string {
  if (!containsEscapes(text)) return text
  const bytes = new TextEncoder().encode(text)
  const out: number[] = []
  let index = 0
  while (index < bytes.length) {
    const byte = bytes[index] ?? 0
    if (byte !== ESCAPE || index + 1 >= bytes.length) {
      out.push(byte)
      index += 1
      continue
    }
    const next = bytes[index + 1] ?? 0
    if (next === OPEN_BRACKET) {
      index = afterCsi(bytes, index, out)
      continue
    }
    if (next === CLOSE_BRACKET) {
      index = afterOsc(bytes, index, out)
      continue
    }
    if (next >= 0x40 && next <= 0x5f) {
      // The two-byte C1 forms.
      index += 2
      continue
    }
    out.push(byte)
    index += 1
  }
  return new TextDecoder().decode(new Uint8Array(out))
}

/** CSI: parameter bytes, then intermediate bytes, then one final byte. */
function afterCsi(bytes: Uint8Array, start: number, out: number[]): number {
  let cursor = start + 2
  while (cursor < bytes.length && inRange(bytes[cursor], 0x30, 0x3f)) cursor += 1
  while (cursor < bytes.length && inRange(bytes[cursor], 0x20, 0x2f)) cursor += 1
  if (cursor < bytes.length && inRange(bytes[cursor], 0x40, 0x7e)) return cursor + 1
  // Unterminated — keep it rather than swallowing the tail.
  out.push(bytes[start] ?? 0)
  return start + 1
}

/** OSC: runs to BEL, or to the ST pair. */
function afterOsc(bytes: Uint8Array, start: number, out: number[]): number {
  let cursor = start + 2
  while (cursor < bytes.length) {
    if (bytes[cursor] === BELL) return cursor + 1
    if (bytes[cursor] === ESCAPE && cursor + 1 < bytes.length && bytes[cursor + 1] === BACKSLASH) {
      return cursor + 2
    }
    cursor += 1
  }
  out.push(bytes[start] ?? 0)
  return start + 1
}

function inRange(value: number | undefined, low: number, high: number): boolean {
  return value !== undefined && value >= low && value <= high
}
