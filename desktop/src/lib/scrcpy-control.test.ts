/**
 * The control encoder, against the same byte vectors ADBKit's
 * `ScrcpyControlMessageTests` asserts.
 *
 * Deliberately the same numbers rather than "whatever this implementation
 * produces": the device's protocol is the contract, both hosts speak it, and a
 * port that agreed only with itself would put every tap in the wrong place with
 * nothing failing.
 */

import { describe, expect, it } from "vitest"

import {
  KEYCODE,
  backOrScreenOn,
  encodeControl,
  i16Fixed,
  injectKeycode,
  injectScroll,
  injectText,
  injectTouch,
  pointFromPointer,
  tapKey,
  u16Fixed,
} from "@/lib/scrcpy-control"

/** A byte range as a plain array, which is what `toEqual` compares against. */
function range(bytes: Uint8Array, start: number, end: number): number[] {
  return Array.from(bytes.subarray(start, end))
}

describe("the wire format", () => {
  it("encodes a keycode in 14 bytes", () => {
    // BACK (4), down, no repeat, no modifiers — ADBKit's own vector.
    expect(Array.from(injectKeycode("down", KEYCODE.back))).toEqual([
      0x00, 0x00, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0,
    ])
  })

  it("encodes text with a big-endian length prefix", () => {
    expect(Array.from(injectText("hi"))).toEqual([0x01, 0, 0, 0, 2, 0x68, 0x69])
  })

  it("encodes a touch in 32 bytes with full pressure", () => {
    const bytes = injectTouch("down", { x: 100, y: 200, width: 800, height: 500 })
    expect(bytes.length).toBe(32)
    // type, then action = down
    expect(bytes[0]).toBe(0x02)
    expect(bytes[1]).toBe(0x00)
    // pointerId, matching the Mac's own 0 rather than scrcpy's mouse sentinel
    expect(range(bytes, 2, 10)).toEqual([0, 0, 0, 0, 0, 0, 0, 0])
    expect(range(bytes, 10, 14)).toEqual([0, 0, 0, 100])
    expect(range(bytes, 14, 18)).toEqual([0, 0, 0, 200])
    // width = 800, height = 500
    expect(range(bytes, 18, 20)).toEqual([0x03, 0x20])
    expect(range(bytes, 20, 22)).toEqual([0x01, 0xf4])
    // pressure 1.0 saturates rather than wrapping to zero
    expect(range(bytes, 22, 24)).toEqual([0xff, 0xff])
  })

  it("releases the pointer with zero pressure", () => {
    // A non-zero pressure on an up leaves the device thinking it is held, which
    // presents as a mirror that registers one tap and then goes dead.
    const bytes = injectTouch("up", { x: 1, y: 2, width: 800, height: 500 })
    expect(range(bytes, 22, 24)).toEqual([0, 0])
  })

  it("encodes backOrScreenOn in 2 bytes", () => {
    expect(Array.from(backOrScreenOn("down"))).toEqual([0x04, 0x00])
  })

  it("encodes a scroll in 21 bytes with signed fixed point", () => {
    const bytes = injectScroll({ x: 10, y: 20, width: 800, height: 500 }, { vertical: 1 })
    expect(bytes.length).toBe(21)
    expect(bytes[0]).toBe(0x03)
    // hscroll 0, then vscroll 1.0
    expect(range(bytes, 13, 15)).toEqual([0x00, 0x00])
    expect(range(bytes, 15, 17)).toEqual([0x7f, 0xff])
  })

  it("scrolls the other way with a negative delta", () => {
    // The reason the amounts are signed: an unsigned encoding scrolls backwards.
    const bytes = injectScroll({ x: 0, y: 0, width: 800, height: 500 }, { vertical: -1 })
    expect(range(bytes, 15, 17)).toEqual([0x80, 0x00])
  })

  it("converts fixed point the way scrcpy does", () => {
    expect(u16Fixed(1)).toBe(0xffff)
    expect(u16Fixed(0)).toBe(0)
    expect(u16Fixed(0.5)).toBe(0x8000)
    expect(i16Fixed(1)).toBe(0x7fff)
    expect(i16Fixed(-1)).toBe(-0x8000)
    expect(i16Fixed(0)).toBe(0)
  })

  it("makes a button click a down and an up", () => {
    const [down, up] = tapKey(KEYCODE.home)
    expect(down?.[1]).toBe(0)
    expect(up?.[1]).toBe(1)
    expect(down === undefined ? [] : range(down, 2, 6)).toEqual([0, 0, 0, 3])
  })

  it("base64s the bytes the protocol carries", () => {
    expect(encodeControl(new Uint8Array([0x04, 0x00]))).toBe("BAA=")
  })
})

describe("mapping a pointer onto the device", () => {
  // A 400×250 element showing an 800×500 video: exactly 1:2, no letterbox.
  const exact = { left: 0, top: 0, width: 400, height: 250 }
  const video = { width: 800, height: 500 }

  it("scales into the video's own coordinates, not the element's", () => {
    // scrcpy scales the point against the size it encodes at, so the element's
    // size would put every tap at half the right place here.
    expect(pointFromPointer({ clientX: 200, clientY: 125 }, exact, video)).toEqual({
      x: 400,
      y: 250,
      width: 800,
      height: 500,
    })
  })

  it("accounts for the letterbox an aspect-preserving fit leaves", () => {
    // A 400×400 element for a 800×500 video fits to 400×250 and centres it, so
    // 75px of black sit above and below.
    const boxed = { left: 0, top: 0, width: 400, height: 400 }
    expect(pointFromPointer({ clientX: 0, clientY: 75 }, boxed, video)).toEqual({
      x: 0,
      y: 0,
      width: 800,
      height: 500,
    })
  })

  it("refuses a tap in the letterbox rather than clamping it", () => {
    // Clamping would land it on the very edge of the screen, which is a real
    // button on most Android UIs — a stray tap is worse than no tap.
    const boxed = { left: 0, top: 0, width: 400, height: 400 }
    expect(pointFromPointer({ clientX: 200, clientY: 10 }, boxed, video)).toBeNull()
    expect(pointFromPointer({ clientX: 200, clientY: 390 }, boxed, video)).toBeNull()
  })

  it("has no answer before the first frame sized the video", () => {
    expect(pointFromPointer({ clientX: 1, clientY: 1 }, exact, { width: 0, height: 0 })).toBeNull()
  })

  it("offsets by the element's position on the page", () => {
    const moved = { left: 100, top: 50, width: 400, height: 250 }
    expect(pointFromPointer({ clientX: 100, clientY: 50 }, moved, video)).toEqual({
      x: 0,
      y: 0,
      width: 800,
      height: 500,
    })
  })
})
