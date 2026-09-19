import { describe, expect, it } from "vitest"
import { formatBytes } from "@/lib/files"
import {
  apply,
  caption,
  DISMISS_AFTER_MS,
  dismissDelay,
  fraction,
  leafName,
  started,
  type PullEvent,
  type PullState,
} from "@/lib/pull-progress"

function state(over: Partial<PullState> = {}): PullState {
  return { ...started("/sdcard/big.zip"), ...over }
}

function event(over: Partial<PullEvent> = {}): PullEvent {
  return { copied: 0, total: null, path: null, done: false, failure: null, ...over }
}

describe("fraction", () => {
  it("is the ratio of copied to total", () => {
    expect(fraction(state({ copied: 50, total: 200 }))).toBeCloseTo(0.25, 8)
  })

  it("is null with no total, so the bar is indeterminate rather than zero", () => {
    // A directory pull has no single total, and a bar sitting at 0% for a
    // minute is a worse lie than one that admits it cannot know.
    expect(fraction(state({ copied: 900, total: null }))).toBeNull()
  })

  it("is null for a zero total rather than dividing by it", () => {
    expect(fraction(state({ copied: 0, total: 0 }))).toBeNull()
  })

  it("never exceeds one", () => {
    // adb writes in blocks and a file system can report the allocated size, so
    // copied briefly passing total is ordinary rather than a bug.
    expect(fraction(state({ copied: 300, total: 200 }))).toBe(1)
  })
})

describe("caption", () => {
  it("counts while the pull runs", () => {
    expect(caption(state({ copied: 1_000, total: 4_000 }))).toBe("1 KB of 4 KB")
  })

  it("counts without a total, rather than saying nothing", () => {
    expect(caption(state({ copied: 1_000, total: null }))).toBe("1 KB copied")
  })

  it("sizes a file exactly as the row being pulled does", () => {
    // 400 MiB — the size the strip and the file list showed differently until
    // the strip stopped dividing by 1024. Two numbers for one file, two rows
    // apart, read as a broken transfer rather than as two conventions.
    const bytes = 419_430_400
    expect(caption(state({ copied: bytes, total: bytes }))).toBe(
      `${formatBytes(bytes)} of ${formatBytes(bytes)}`,
    )
    expect(formatBytes(bytes)).toBe("419 MB")
  })

  it("says where it landed once it is done", () => {
    const done = state({ done: true, landedAt: "/home/me/Downloads/big.zip" })
    expect(caption(done)).toBe("Saved to /home/me/Downloads/big.zip")
  })

  it("prefers adb's own words over anything it made up", () => {
    const failed = state({ done: true, failure: "adb: no such file or directory" })
    expect(caption(failed)).toBe("adb: no such file or directory")
  })
})

describe("leafName", () => {
  it("takes the last component of either separator", () => {
    expect(leafName("/sdcard/DCIM/photo.png")).toBe("photo.png")
    expect(leafName("C:\\Users\\me\\clip.mp4")).toBe("clip.mp4")
  })

  it("ignores a trailing slash, as a directory path has", () => {
    expect(leafName("/sdcard/DCIM/")).toBe("DCIM")
  })
})

describe("apply", () => {
  it("takes the numbers from the event", () => {
    const next = apply(started("/sdcard/x"), event({ copied: 10, total: 100 }))
    expect(next).toMatchObject({ copied: 10, total: 100, done: false })
  })

  it("keeps the landing place once it has one", () => {
    // The daemon sends the path on the last event only; a later render must
    // not lose it.
    const done = apply(started("/sdcard/x"), event({ done: true, path: "/tmp/x" }))
    expect(apply(done, event({ copied: 1, total: 1 })).landedAt).toBe("/tmp/x")
  })

  it("keeps the failure once it has one", () => {
    const failed = apply(started("/sdcard/x"), event({ done: true, failure: "boom" }))
    expect(apply(failed, event()).failure).toBe("boom")
  })

  it("leaves the device path alone — the event does not carry it", () => {
    expect(apply(started("/sdcard/x"), event({ path: "/tmp/x" })).path).toBe("/sdcard/x")
  })
})

describe("dismissDelay", () => {
  it("is nothing while the pull runs", () => {
    expect(dismissDelay(state())).toBeNull()
  })

  it("clears a finished pull after a moment", () => {
    expect(dismissDelay(state({ done: true }))).toBe(DISMISS_AFTER_MS)
  })

  it("leaves a failure up until it is dismissed", () => {
    // An error that vanishes on its own is an error nobody read.
    expect(dismissDelay(state({ done: true, failure: "boom" }))).toBeNull()
  })
})
