/**
 * scrcpy's control messages, encoded.
 *
 * The device's own protocol, so the layout is not ours to choose — this is a
 * port of ADBKit's `ScrcpyControlMessage`, which the Mac uses, and the tests
 * assert the same byte vectors. Every field is big-endian.
 *
 * Pure: bytes out, no transport. `useMirror` sends them; the daemon forwards
 * them to the control socket verbatim.
 */

/** Message types, from scrcpy's `control_msg.h`. */
const TYPE_INJECT_KEYCODE = 0
const TYPE_INJECT_TEXT = 1
const TYPE_INJECT_TOUCH = 2
const TYPE_INJECT_SCROLL = 3
const TYPE_BACK_OR_SCREEN_ON = 4

export type KeyAction = "down" | "up"
export type TouchAction = "down" | "up" | "move"

const KEY_ACTIONS: Record<KeyAction, number> = { down: 0, up: 1 }
const TOUCH_ACTIONS: Record<TouchAction, number> = { down: 0, up: 1, move: 2 }

/**
 * Android keycodes, for the buttons the mirror offers.
 *
 * Only the ones the pane actually has — a full table would be a list of
 * constants nothing reads.
 */
export const KEYCODE = {
  back: 4,
  home: 3,
  appSwitch: 187,
  volumeUp: 24,
  volumeDown: 25,
  volumeMute: 164,
  power: 26,
} as const

/**
 * A touch, in the frame's own coordinates.
 *
 * `width`/`height` are the *video's* dimensions, not the element's: scrcpy
 * scales the point against the size it is encoding at, so passing the on-screen
 * size would put every tap in the wrong place on any pane that is not exactly
 * 1:1. The caller converts, and `pointFromPointer` is how.
 */
export interface TouchPoint {
  x: number
  y: number
  width: number
  height: number
}

/**
 * `injectTouch`: 32 bytes.
 *
 * The pointer id, action button and buttons are all 0, which is what the Mac
 * sends (`MirrorViewModel.touch`) and what devices are known to accept — not
 * scrcpy's `POINTER_ID_MOUSE` sentinel. Parity beats cleverness here: these
 * values are proven against real hardware and the port is not the place to
 * find out otherwise.
 *
 * Pressure is a 16-bit fixed-point fraction and must be 0 on an `up` — a
 * non-zero pressure there reads as a finger still down, leaving the device
 * thinking it is being held.
 */
export function injectTouch(action: TouchAction, point: TouchPoint): Uint8Array {
  const writer = new Writer(32)
  writer.u8(TYPE_INJECT_TOUCH)
  writer.u8(TOUCH_ACTIONS[action])
  writer.u64(0n)
  writer.position(point)
  writer.u16(u16Fixed(action === "up" ? 0 : 1))
  writer.u32(0)
  writer.u32(0)
  return writer.done()
}

/**
 * `sc_float_to_u16fp`: a normalized [0,1] float as 16-bit fixed point.
 *
 * Ported rather than approximated, because 1.0 is *not* 0x10000 — it saturates
 * to 0xffff, and a decoder reading the truncated low half would see no pressure
 * at all.
 */
export function u16Fixed(value: number): number {
  const clamped = Math.max(0, Math.min(1, value))
  return Math.min(0xffff, Math.trunc(clamped * 65_536))
}

/** `sc_float_to_i16fp`: a normalized [-1,1] float as signed 16-bit fixed point. */
export function i16Fixed(value: number): number {
  const clamped = Math.max(-1, Math.min(1, value))
  const scaled = Math.trunc(clamped * 32_768)
  if (scaled >= 0x7fff) return 0x7fff
  if (scaled <= -0x8000) return -0x8000
  return scaled
}

/** `injectKeycode`: 14 bytes. */
export function injectKeycode(
  action: KeyAction,
  keycode: number,
  { repeat = 0, metaState = 0 }: { repeat?: number; metaState?: number } = {},
): Uint8Array {
  const writer = new Writer(14)
  writer.u8(TYPE_INJECT_KEYCODE)
  writer.u8(KEY_ACTIONS[action])
  writer.u32(keycode)
  writer.u32(repeat)
  writer.u32(metaState)
  return writer.done()
}

/** A whole key press, which is what a button click is. */
export function tapKey(keycode: number): Uint8Array[] {
  return [injectKeycode("down", keycode), injectKeycode("up", keycode)]
}

/**
 * `backOrScreenOn`: wakes a sleeping device rather than only going back.
 *
 * This is what scrcpy's own Back button sends, and the difference matters — a
 * plain `KEYCODE_BACK` on a sleeping device does nothing visible, so the mirror
 * would look broken at exactly the moment someone is trying to wake it.
 */
export function backOrScreenOn(action: KeyAction): Uint8Array {
  const writer = new Writer(2)
  writer.u8(TYPE_BACK_OR_SCREEN_ON)
  writer.u8(KEY_ACTIONS[action])
  return writer.done()
}

/** `injectText`, for a paste. */
export function injectText(text: string): Uint8Array {
  const bytes = new TextEncoder().encode(text)
  const writer = new Writer(5 + bytes.length)
  writer.u8(TYPE_INJECT_TEXT)
  writer.u32(bytes.length)
  writer.bytes(bytes)
  return writer.done()
}

/**
 * `injectScroll`: 21 bytes.
 *
 * The two scroll amounts are *signed* 16-bit fixed point, which is why they go
 * through their own conversion — a negative wheel delta encoded as unsigned
 * scrolls the wrong way.
 */
export function injectScroll(
  point: TouchPoint,
  { horizontal = 0, vertical = 0 }: { horizontal?: number; vertical?: number },
): Uint8Array {
  const writer = new Writer(21)
  writer.u8(TYPE_INJECT_SCROLL)
  writer.position(point)
  writer.i16(i16Fixed(horizontal))
  writer.i16(i16Fixed(vertical))
  writer.u32(0)
  return writer.done()
}

/**
 * A pointer event's position in the video's coordinates.
 *
 * `letterbox` is the gap the aspect-preserving fit leaves — a tap in the black
 * bars is not a tap on the device, and clamping instead of rejecting would put
 * it on the edge of the screen, which is a real button on most Android UIs.
 */
export function pointFromPointer(
  event: { clientX: number; clientY: number },
  rect: { left: number; top: number; width: number; height: number },
  video: { width: number; height: number },
): TouchPoint | null {
  if (video.width <= 0 || video.height <= 0 || rect.width <= 0 || rect.height <= 0) return null
  const scale = Math.min(rect.width / video.width, rect.height / video.height)
  const drawnWidth = video.width * scale
  const drawnHeight = video.height * scale
  const offsetX = (rect.width - drawnWidth) / 2
  const offsetY = (rect.height - drawnHeight) / 2
  const x = (event.clientX - rect.left - offsetX) / scale
  const y = (event.clientY - rect.top - offsetY) / scale
  if (x < 0 || y < 0 || x > video.width || y > video.height) return null
  return {
    x: Math.round(x),
    y: Math.round(y),
    width: video.width,
    height: video.height,
  }
}

/** Base64, which is how the stream protocol carries bytes. */
export function encodeControl(bytes: Uint8Array): string {
  let binary = ""
  for (const byte of bytes) {
    // One byte per code unit, which is what `btoa` wants — `fromCodePoint`
    // would fuse values above 0x7f into characters no byte can hold, the same
    // trap `lib/terminal.ts` names.
    // oxlint-disable-next-line unicorn/prefer-code-point
    binary += String.fromCharCode(byte)
  }
  return btoa(binary)
}

/** A fixed-size big-endian writer, so each message states its own length. */
class Writer {
  private readonly view: DataView
  private readonly buffer: Uint8Array
  private offset = 0

  constructor(size: number) {
    this.buffer = new Uint8Array(size)
    this.view = new DataView(this.buffer.buffer)
  }

  u8(value: number): void {
    this.view.setUint8(this.offset, value)
    this.offset += 1
  }

  u16(value: number): void {
    this.view.setUint16(this.offset, value)
    this.offset += 2
  }

  u32(value: number): void {
    this.view.setUint32(this.offset, value)
    this.offset += 4
  }

  u64(value: bigint): void {
    this.view.setBigUint64(this.offset, value)
    this.offset += 8
  }

  /** x and y are signed 32-bit; width and height unsigned 16-bit. */
  position(point: TouchPoint): void {
    this.view.setInt32(this.offset, point.x)
    this.view.setInt32(this.offset + 4, point.y)
    this.view.setUint16(this.offset + 8, point.width)
    this.view.setUint16(this.offset + 10, point.height)
    this.offset += 12
  }

  i16(value: number): void {
    this.view.setInt16(this.offset, value)
    this.offset += 2
  }

  bytes(source: Uint8Array): void {
    this.buffer.set(source, this.offset)
    this.offset += source.length
  }

  done(): Uint8Array {
    return this.buffer
  }
}
