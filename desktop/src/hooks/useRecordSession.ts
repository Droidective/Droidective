import { useCallback, useEffect, useRef, useState } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import {
  asDaemonError,
  recordPause,
  recordResume,
  recordStart,
  recordStatus,
  recordStop,
  type RecordStatus,
  type StoppedRecording,
} from "@/lib/daemon"
import { elapsedSeconds, reachedTimeLimit, type RecordOptions } from "@/lib/record"

export interface RecordSession {
  status: RecordStatus | null
  /** Seconds of video so far, counted here between the daemon's answers. */
  elapsed: number
  busy: boolean
  /** Set by `stop`, cleared once it has been saved or discarded. */
  finished: StoppedRecording | null
  clearFinished: () => void
  start: (serial: string, options: RecordOptions) => void
  pause: () => void
  resume: (options: RecordOptions) => void
  stop: () => void
}

/**
 * The recording itself: what the daemon says is running, the clock over it,
 * and the four verbs.
 *
 * The elapsed time ticks locally between answers rather than over a socket — a
 * stream topic carrying one number once a second would be a lot of machinery
 * for a value the client can count. The **time limit** is enforced here for the
 * reason the Mac enforces it in the view: it is a preference about when to
 * press Stop, not something the encoder knows about.
 */
export function useRecordSession(): RecordSession {
  const [status, setStatus] = useState<RecordStatus | null>(null)
  const [elapsed, setElapsed] = useState(0)
  const [busy, setBusy] = useState(false)
  const [finished, setFinished] = useState<StoppedRecording | null>(null)
  const { show } = useNotifications()

  /** When the daemon's `elapsedSeconds` was read, and whether it is running. */
  const base = useRef<{ seconds: number; since: number | null }>({ seconds: 0, since: null })
  const limit = useRef(0)
  /** Stop is re-entrant through the time limit, so it is claimed as a ref. */
  const stopping = useRef(false)

  const adopt = useCallback((next: RecordStatus) => {
    setStatus(next)
    base.current = {
      seconds: next.elapsedSeconds,
      since: next.recording && !next.paused ? Date.now() : null,
    }
    setElapsed(next.elapsedSeconds)
  }, [])

  const report = useCallback(
    (thrown: unknown) => {
      show({ message: asDaemonError(thrown).message, ok: false })
    },
    [show],
  )

  useAdoptRunningRecording(adopt, report)

  const stop = useCallback(() => {
    if (stopping.current) return
    stopping.current = true
    setBusy(true)
    recordStop().then(
      (result) => {
        stopping.current = false
        setBusy(false)
        setFinished(result)
        setStatus(null)
        base.current = { seconds: 0, since: null }
        setElapsed(0)
      },
      (thrown: unknown) => {
        stopping.current = false
        setBusy(false)
        setStatus(null)
        report(thrown)
      },
    )
  }, [report])

  useRecordClock({ status, base, limit, setElapsed, stop })

  const run = useCallback(
    (action: () => Promise<RecordStatus>) => {
      setBusy(true)
      action().then(
        (next) => {
          setBusy(false)
          adopt(next)
        },
        (thrown: unknown) => {
          setBusy(false)
          report(thrown)
        },
      )
    },
    [adopt, report],
  )

  return {
    status,
    elapsed,
    busy,
    finished,
    start: useCallback(
      (serial: string, options: RecordOptions) => {
        limit.current = options.timeLimitSeconds
        setFinished(null)
        run(() => recordStart(serial, wire(options)))
      },
      [run],
    ),
    pause: useCallback(() => {
      run(() => recordPause())
    }, [run]),
    resume: useCallback(
      (options: RecordOptions) => {
        run(() => recordResume(wire(options)))
      },
      [run],
    ),
    stop,
    clearFinished: useCallback(() => {
      setFinished(null)
    }, []),
  }
}

/** The daemon takes the three scrcpy knobs; the time limit never leaves here. */
function wire(options: RecordOptions) {
  return {
    maxSize: options.maxSize,
    bitRateMbps: options.bitRateMbps,
    maxFps: options.maxFps,
  }
}

/**
 * Adopt whatever is already recording.
 *
 * Asked once on open, because a recording started before this screen was
 * opened — from another window, or before it was closed — is the case a purely
 * local state gets wrong.
 */
function useAdoptRunningRecording(
  adopt: (status: RecordStatus) => void,
  report: (thrown: unknown) => void,
) {
  useEffect(() => {
    let cancelled = false
    recordStatus().then(
      (next) => {
        if (!cancelled) adopt(next)
      },
      (thrown: unknown) => {
        if (!cancelled) report(thrown)
      },
    )
    return () => {
      cancelled = true
    }
  }, [adopt, report])
}

/**
 * The elapsed clock, and the time limit with it.
 *
 * One interval rather than two, so a limit can never fire against an elapsed
 * value from the previous tick.
 */
function useRecordClock({
  status,
  base,
  limit,
  setElapsed,
  stop,
}: {
  status: RecordStatus | null
  base: { current: { seconds: number; since: number | null } }
  limit: { current: number }
  setElapsed: (seconds: number) => void
  stop: () => void
}) {
  useEffect(() => {
    if (status === null || !status.recording || status.paused) return
    const tick = setInterval(() => {
      const now = elapsedSeconds(base.current.seconds, base.current.since, Date.now())
      setElapsed(now)
      if (reachedTimeLimit(now, limit.current)) stop()
    }, 250)
    return () => {
      clearInterval(tick)
    }
  }, [status, base, limit, setElapsed, stop])
}
