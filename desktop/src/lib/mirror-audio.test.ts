import { describe, expect, it } from "vitest"

import {
  chunkSeconds,
  deinterleave,
  nextStart,
  RAW_CHANNELS,
  RAW_SAMPLE_RATE,
  SCHEDULE_CUSHION_SECONDS,
} from "@/lib/mirror-audio"

/** Two stereo frames: L=1, R=-1, then L=32767, R=-32768. */
function stereo(): Uint8Array {
  const bytes = new Uint8Array(8)
  const view = new DataView(bytes.buffer)
  view.setInt16(0, 1, true)
  view.setInt16(2, -1, true)
  view.setInt16(4, 32_767, true)
  view.setInt16(6, -32_768, true)
  return bytes
}

describe("deinterleave", () => {
  it("splits interleaved frames into one array per channel", () => {
    const [left, right] = deinterleave(stereo(), 2)
    expect(left).toHaveLength(2)
    expect(right).toHaveLength(2)
    expect(left?.[0]).toBeCloseTo(1 / 32_768)
    expect(right?.[0]).toBeCloseTo(-1 / 32_768)
  })

  it("reads little-endian, which is what s16le means", () => {
    // Read big-endian, 1 becomes 256 — a 48 dB error that would be obvious
    // once and subtle forever after.
    const [left] = deinterleave(stereo(), 2)
    expect(left?.[0]).not.toBeCloseTo(256 / 32_768)
  })

  it("keeps full scale inside −1…1", () => {
    // Dividing by 32767 would let the negative extreme reach −1.000030, which
    // clips in Web Audio rather than rounding.
    const [left, right] = deinterleave(stereo(), 2)
    expect(left?.[1]).toBeLessThan(1)
    expect(right?.[1]).toBe(-1)
  })

  it("drops a trailing partial frame rather than padding it", () => {
    // scrcpy sends whole frames, so a remainder is a truncated chunk — half a
    // sample rendered as silence is a click.
    const odd = new Uint8Array([0, 0, 0, 0, 7])
    expect(deinterleave(odd, 2)[0]).toHaveLength(1)
  })

  it("handles mono, and refuses a channel count that is not one", () => {
    expect(deinterleave(stereo(), 1)).toHaveLength(1)
    expect(deinterleave(stereo(), 1)[0]).toHaveLength(4)
    expect(deinterleave(stereo(), 0)).toEqual([])
  })

  it("returns empty channels for an empty chunk", () => {
    for (const channel of deinterleave(new Uint8Array(0), 2)) {
      expect(channel).toHaveLength(0)
    }
  })
})

describe("chunkSeconds", () => {
  it("measures a chunk at scrcpy's own format", () => {
    // One second of 48 kHz stereo s16 is 192 000 bytes.
    expect(chunkSeconds(192_000, RAW_SAMPLE_RATE, RAW_CHANNELS)).toBeCloseTo(1)
  })

  it("is zero for a format that cannot describe anything", () => {
    expect(chunkSeconds(192_000, 0, 2)).toBe(0)
    expect(chunkSeconds(192_000, 48_000, 0)).toBe(0)
  })
})

describe("nextStart", () => {
  it("queues a chunk after the one before it while the stream keeps up", () => {
    // Playing each at "now" instead would start them ~20 ms apart in wall time
    // while each lasts 21.3 ms, and the drift is audible within seconds.
    expect(nextStart(10.5, 10.2, SCHEDULE_CUSHION_SECONDS)).toBe(10.5)
  })

  it("restarts from now when the queue has drained", () => {
    // A stall: scheduling into the past plays the buffer immediately and leaves
    // every later one still behind.
    expect(nextStart(9.9, 10.2, 0.04)).toBeCloseTo(10.24)
  })

  it("treats exactly-now as still keeping up", () => {
    expect(nextStart(10.2, 10.2, 0.04)).toBe(10.2)
  })
})
