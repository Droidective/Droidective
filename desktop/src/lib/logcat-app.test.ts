import { describe, expect, it } from "vitest"

import {
  APP_FILTER_OFF,
  appFilterLabel,
  needsRestart,
  nextAppFilter,
  pollDelayMs,
  streamPid,
  type AppFilter,
} from "@/lib/logcat-app"

const waiting: AppFilter = { kind: "waiting", packageId: "com.example.app" }
const streaming: AppFilter = { kind: "streaming", packageId: "com.example.app", pid: 4211 }

describe("nextAppFilter", () => {
  it("turns off when no app is chosen", () => {
    expect(nextAppFilter(streaming, null, 4211)).toEqual(APP_FILTER_OFF)
  })

  it("waits for an app that is not running", () => {
    // The decision the whole thing turns on: not running is the ordinary state
    // of an app whose log you opened first, and streaming the whole device
    // instead would be a filter that quietly does nothing.
    expect(nextAppFilter(APP_FILTER_OFF, "com.example.app", null)).toEqual(waiting)
  })

  it("streams once the app has a pid", () => {
    expect(nextAppFilter(waiting, "com.example.app", 4211)).toEqual(streaming)
  })

  it("follows the app to a new pid", () => {
    // A relaunch. `logcat --pid` goes silent forever on the old one, so this is
    // the difference between a live feed and one that looks alive.
    expect(nextAppFilter(streaming, "com.example.app", 5000)).toEqual({
      kind: "streaming",
      packageId: "com.example.app",
      pid: 5000,
    })
  })

  it("drops an answer about an app nobody is asking about now", () => {
    // The request was in flight when the choice changed. Applying it would
    // filter the log to the previous app and say it was the new one.
    expect(nextAppFilter(streaming, "com.other.app", 4211)).toEqual(streaming)
  })

  it("notices an app that stopped", () => {
    expect(nextAppFilter(streaming, "com.example.app", null)).toEqual(waiting)
  })
})

describe("needsRestart", () => {
  it("restarts when the pid moves", () => {
    expect(needsRestart(streaming, { ...streaming, pid: 5000 })).toBe(true)
  })

  it("does not restart when the same pid is seen again", () => {
    // Re-read every three seconds; restarting here would clear the feed that
    // often, which is the bug this guard exists for.
    expect(needsRestart(streaming, { ...streaming })).toBe(false)
  })

  it("restarts when the filter is turned on and off", () => {
    expect(needsRestart(APP_FILTER_OFF, streaming)).toBe(true)
    expect(needsRestart(streaming, APP_FILTER_OFF)).toBe(true)
  })

  it("does not restart between off and waiting", () => {
    // Both stream the whole device — nothing has changed about the
    // subscription, only about what the pane says it is doing.
    expect(needsRestart(APP_FILTER_OFF, waiting)).toBe(false)
  })
})

describe("streamPid", () => {
  it("is the pid only while streaming", () => {
    expect(streamPid(streaming)).toBe(4211)
    expect(streamPid(waiting)).toBeNull()
    expect(streamPid(APP_FILTER_OFF)).toBeNull()
  })
})

describe("pollDelayMs", () => {
  it("asks nothing with no app chosen", () => {
    expect(pollDelayMs(APP_FILTER_OFF)).toBeNull()
  })

  it("checks more often while someone is waiting for a launch", () => {
    const waitingDelay = pollDelayMs(waiting)
    const streamingDelay = pollDelayMs(streaming)
    expect(waitingDelay).not.toBeNull()
    expect(streamingDelay).not.toBeNull()
    expect(waitingDelay as number).toBeLessThan(streamingDelay as number)
  })
})

describe("appFilterLabel", () => {
  it("says which of the two empty feeds this is", () => {
    // `waiting` and `off` both stream nothing app-specific, and they mean
    // opposite things — so the label is what stops an empty log being read as
    // a broken one.
    expect(appFilterLabel(APP_FILTER_OFF)).toBe("All apps")
    expect(appFilterLabel(waiting)).toContain("Waiting for com.example.app")
    expect(appFilterLabel(streaming)).toContain("pid 4211")
  })
})
