/**
 * The three rules a mirror client owes the daemon, tested without a decoder.
 *
 * They are written down in §5.4 of `docs/droidectived-protocol.md` because
 * ignoring any of them fails quietly: a decoder fed too early throws and stays
 * dead, and one fed after a gap renders garbage rather than showing a gap.
 */

import { afterEach, describe, expect, it, vi } from "vitest"

import {
  codecSupport,
  decodeFrame,
  MAX_PENDING_FRAMES,
  missingCodecHint,
  newGate,
  noteGap,
  replayable,
  stepMirror,
  type DecodeStep,
} from "@/lib/mirror"
import type { MirrorFrame } from "@/lib/wire"

const CONFIG: MirrorFrame = {
  kind: "config",
  codec: "avc1.42C029",
  width: 800,
  height: 500,
  deviceName: "sdk_gphone64_arm64",
}

/** base64 of [0, 0, 0, 1, 0x65] — a start code and an IDR header. */
const KEY_DATA = "AAAAAWU="

function frame(key: boolean, pts = 1): MirrorFrame {
  return { kind: "frame", key, pts, data: KEY_DATA }
}

describe("the config gate", () => {
  it("skips frames that arrive before a config", () => {
    // A decoder fed before `configure` throws, and the throw is terminal.
    const { step } = stepMirror(newGate(), frame(true))
    expect(step).toEqual({ do: "skip", why: "unconfigured" })
  })

  it("configures from a config payload", () => {
    const { gate, step } = stepMirror(newGate(), CONFIG)
    expect(step).toEqual({
      do: "configure",
      codec: "avc1.42C029",
      width: 800,
      height: 500,
      deviceName: "sdk_gphone64_arm64",
    })
    expect(gate.configured).toBe(true)
  })

  it("decodes once configured", () => {
    const configured = stepMirror(newGate(), CONFIG).gate
    const { step } = stepMirror(configured, frame(false, 999))
    expect(step).toMatchObject({ do: "decode", type: "delta", timestamp: 999 })
  })

  it("refuses a config that is missing what configure needs", () => {
    // Half a config would configure a decoder with an undefined codec, which
    // throws — better to stay unconfigured and wait for a real one.
    const { gate, step } = stepMirror(newGate(), { kind: "config", codec: "avc1.42C029" })
    expect(step).toEqual({ do: "skip", why: "malformed" })
    expect(gate.configured).toBe(false)
  })
})

describe("recovering from a gap", () => {
  it("discards deltas until the next keyframe", () => {
    // The daemon's buffer dropped frames, so the ones after the gap reference
    // pictures this decoder never saw.
    let gate = stepMirror(newGate(), CONFIG).gate
    gate = noteGap(gate)

    const afterGap = stepMirror(gate, frame(false, 2))
    expect(afterGap.step).toEqual({ do: "skip", why: "awaiting-key" })

    const onKey = stepMirror(afterGap.gate, frame(true, 3))
    expect(onKey.step).toMatchObject({ do: "decode", type: "key" })
    expect(onKey.gate.awaitingKey).toBe(false)
  })

  it("keeps decoding normally once recovered", () => {
    let gate = noteGap(stepMirror(newGate(), CONFIG).gate)
    gate = stepMirror(gate, frame(true, 1)).gate
    expect(stepMirror(gate, frame(false, 2)).step).toMatchObject({ do: "decode" })
  })

  it("does not un-configure the decoder", () => {
    // Re-configuring would throw away the frames still in flight for no gain:
    // the codec did not change, only the continuity did.
    const gate = noteGap(stepMirror(newGate(), CONFIG).gate)
    expect(gate.configured).toBe(true)
  })

  it("clears the wait when a new config arrives", () => {
    // The parameter sets just changed, so nothing queued for the old ones is
    // worth waiting for.
    const gate = noteGap(stepMirror(newGate(), CONFIG).gate)
    expect(stepMirror(gate, CONFIG).gate.awaitingKey).toBe(false)
  })
})

describe("malformed payloads", () => {
  it("skips a frame whose data is not base64", () => {
    const gate = stepMirror(newGate(), CONFIG).gate
    const { step } = stepMirror(gate, { kind: "frame", key: true, pts: 1, data: "!!not base64!!" })
    expect(step).toEqual({ do: "skip", why: "malformed" })
  })

  it("skips a frame with no timestamp", () => {
    const gate = stepMirror(newGate(), CONFIG).gate
    const { step } = stepMirror(gate, { kind: "frame", key: true, data: KEY_DATA })
    expect(step).toEqual({ do: "skip", why: "malformed" })
  })

  it("decodes base64 to the bytes it stands for", () => {
    expect([...(decodeFrame(KEY_DATA) ?? [])]).toEqual([0, 0, 0, 1, 0x65])
  })

  it("returns null rather than throwing on bad base64", () => {
    expect(decodeFrame("!!!")).toBeNull()
  })
})

describe("the codec probe", () => {
  afterEach(() => {
    // oxlint-disable-next-line no-explicit-any
    delete (globalThis as any).VideoDecoder
    vi.restoreAllMocks()
  })

  it("reports a webview with no VideoDecoder at all", async () => {
    const support = await codecSupport("avc1.42C029")
    expect(support.ok).toBe(false)
    expect(support.hint).toContain("VideoDecoder")
  })

  it("passes a codec the webview supports", async () => {
    // oxlint-disable-next-line no-explicit-any
    ;(globalThis as any).VideoDecoder = {
      isConfigSupported: vi.fn().mockResolvedValue({ supported: true }),
    }
    expect(await codecSupport("avc1.42C029")).toEqual({ ok: true, hint: null })
  })

  it("names the missing package when H.264 is unsupported", async () => {
    // The measured case: WebKitGTK has VideoDecoder and no H.264 until
    // gstreamer1.0-libav is installed. Without this the mirror is a black
    // rectangle — see scripts/probe-webkit-webcodecs.sh.
    // oxlint-disable-next-line no-explicit-any
    ;(globalThis as any).VideoDecoder = {
      isConfigSupported: vi.fn().mockResolvedValue({ supported: false }),
    }
    const support = await codecSupport("avc1.42C029")
    expect(support.ok).toBe(false)
    expect(support.hint).toContain("gstreamer1.0-libav")
  })

  it("treats a codec string the webview refuses to parse as unsupported", async () => {
    // oxlint-disable-next-line no-explicit-any
    ;(globalThis as any).VideoDecoder = {
      isConfigSupported: vi.fn().mockRejectedValue(new TypeError("bad codec")),
    }
    expect((await codecSupport("nonsense")).ok).toBe(false)
  })

  it("names the codec and both package spellings in the hint", () => {
    const hint = missingCodecHint("avc1.640028")
    expect(hint).toContain("avc1.640028")
    expect(hint).toContain("gstreamer1.0-libav")
    expect(hint).toContain("gstreamer1-libav")
  })
})

/**
 * The window between a `config` payload and a usable decoder.
 *
 * `configure` awaits `VideoDecoder.isConfigSupported`, and scrcpy sends its
 * first keyframe immediately after the config packet — inside that await. The
 * frames are held rather than dropped, because dropping the keyframe left every
 * following delta referencing pictures no decoder had, and WebCodecs ends the
 * session over it ("Key frame is required"). Found by opening the mirror
 * against a real emulator, not by reading this.
 */
function chunk(type: "key" | "delta", timestamp: number): DecodeStep {
  return { do: "decode", type, timestamp, data: new Uint8Array([timestamp]) }
}

describe("replayable", () => {
  it("replays from the first keyframe, dropping the deltas before it", () => {
    const replay = replayable([
      chunk("delta", 1),
      chunk("delta", 2),
      chunk("key", 3),
      chunk("delta", 4),
    ])
    expect(replay.map((one) => one.timestamp)).toEqual([3, 4])
  })

  it("starts at the keyframe when it is the first frame in the window", () => {
    const replay = replayable([chunk("key", 1), chunk("delta", 2)])
    expect(replay.map((one) => one.timestamp)).toEqual([1, 2])
  })

  it("replays nothing when the window holds no keyframe", () => {
    // The caller waits for the next one rather than feeding the decoder a
    // chunk it must reject — the whole point of the queue.
    expect(replayable([chunk("delta", 1), chunk("delta", 2)])).toEqual([])
  })

  it("replays nothing for an empty window", () => {
    expect(replayable([])).toEqual([])
  })

  it("keeps every frame from the keyframe on, in order", () => {
    const window = [chunk("key", 1), ...Array.from({ length: 30 }, (_, i) => chunk("delta", i + 2))]
    const replay = replayable(window)
    expect(replay).toHaveLength(31)
    expect(replay.map((one) => one.timestamp)).toEqual(window.map((one) => one.timestamp))
  })

  it("caps the window at a few seconds of live video", () => {
    // A bound, not a number worth pinning: past it the backlog is stale enough
    // that the next keyframe is the better start.
    expect(MAX_PENDING_FRAMES).toBeGreaterThan(60)
    expect(MAX_PENDING_FRAMES).toBeLessThanOrEqual(600)
  })
})
