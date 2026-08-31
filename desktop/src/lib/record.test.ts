import { describe, expect, it } from "vitest"

import {
  durationLabel,
  elapsedSeconds,
  fileSizeLabel,
  reachedTimeLimit,
  recordingFileName,
} from "@/lib/record"

describe("durationLabel", () => {
  it("counts in minutes and seconds, and adds hours only past one", () => {
    expect(durationLabel(0)).toBe("00:00")
    expect(durationLabel(9)).toBe("00:09")
    expect(durationLabel(75)).toBe("01:15")
    expect(durationLabel(3599)).toBe("59:59")
    expect(durationLabel(3600)).toBe("1:00:00")
    expect(durationLabel(3725)).toBe("1:02:05")
  })

  it("rounds down and refuses to go negative", () => {
    expect(durationLabel(9.9)).toBe("00:09")
    expect(durationLabel(-5)).toBe("00:00")
  })
})

describe("elapsedSeconds", () => {
  /**
   * The clock counts recording, not wall time. A recording paused for a minute
   * has not gained a minute of video, and a timer saying otherwise would
   * disagree with the file that comes out.
   */
  it("holds still while paused", () => {
    expect(elapsedSeconds(42, null, 1_000_000)).toBe(42)
  })

  it("adds the time since it last started counting", () => {
    expect(elapsedSeconds(10, 1_000_000, 1_003_500)).toBeCloseTo(13.5, 5)
  })

  /**
   * A clock that ran backwards would show a shrinking recording. It cannot
   * happen from a monotonic source, but `Date.now()` is not one — a system
   * clock adjustment mid-recording is exactly the case.
   */
  it("never goes backwards if the clock does", () => {
    expect(elapsedSeconds(10, 1_000_000, 999_000)).toBe(10)
  })
})

describe("reachedTimeLimit", () => {
  /**
   * Zero is "unlimited", and the separate check is what stops it firing the
   * instant recording starts — nought elapsed is otherwise ≥ a limit of nought.
   */
  it("never fires for an unlimited recording", () => {
    expect(reachedTimeLimit(0, 0)).toBe(false)
    expect(reachedTimeLimit(9_999, 0)).toBe(false)
  })

  it("fires at the limit and past it", () => {
    expect(reachedTimeLimit(59.9, 60)).toBe(false)
    expect(reachedTimeLimit(60, 60)).toBe(true)
    expect(reachedTimeLimit(61, 60)).toBe(true)
  })
})

describe("recordingFileName", () => {
  it("stamps the file so two recordings never collide", () => {
    const name = recordingFileName(new Date(2026, 7, 31, 9, 5, 3))
    expect(name).toBe("recording_20260831_090503.mp4")
  })
})

describe("fileSizeLabel", () => {
  it("steps from bytes to megabytes", () => {
    expect(fileSizeLabel(512)).toBe("512 B")
    expect(fileSizeLabel(2048)).toBe("2.0 KB")
    expect(fileSizeLabel(3_145_728)).toBe("3.0 MB")
  })
})
