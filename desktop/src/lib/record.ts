/**
 * Screen recording's decisions, without the recording.
 *
 * The Mac's `ScreenRecordView` holds these inline; here they are pure so the
 * ones that are easy to get subtly wrong — an elapsed clock that counts paused
 * time, a time limit that fires again after a resume — can be tested without a
 * device.
 */

export interface RecordOptions {
  /** Longest side in px; 0 is the device's own size. */
  maxSize: number
  /** Video bit-rate in Mbps; 0 is scrcpy's default. */
  bitRateMbps: number
  /** Frame-rate cap; 0 is unlimited. */
  maxFps: number
  /** Stop after N seconds; 0 is unlimited. Enforced here, not by the daemon. */
  timeLimitSeconds: number
}

export const DEFAULT_RECORD_OPTIONS: RecordOptions = {
  maxSize: 0,
  bitRateMbps: 0,
  maxFps: 0,
  timeLimitSeconds: 0,
}

/** The Mac's four pickers, with its wording and its values. */
export const RESOLUTION_CHOICES: { value: number; label: string }[] = [
  { value: 0, label: "Device" },
  { value: 1920, label: "1920 px" },
  { value: 1280, label: "1280 px" },
  { value: 1024, label: "1024 px" },
  { value: 800, label: "800 px" },
]

export const BIT_RATE_CHOICES: { value: number; label: string }[] = [
  { value: 0, label: "Default" },
  { value: 2, label: "2 Mbps" },
  { value: 4, label: "4 Mbps" },
  { value: 8, label: "8 Mbps" },
  { value: 16, label: "16 Mbps" },
]

export const FPS_CHOICES: { value: number; label: string }[] = [
  { value: 0, label: "Unlimited" },
  { value: 30, label: "30" },
  { value: 60, label: "60" },
  { value: 120, label: "120" },
]

export const TIME_LIMIT_CHOICES: { value: number; label: string }[] = [
  { value: 0, label: "Unlimited" },
  { value: 60, label: "1 min" },
  { value: 180, label: "3 min" },
  { value: 300, label: "5 min" },
  { value: 600, label: "10 min" },
]

/** Two digits, which both the clock and the file stamp want. */
function pad(value: number): string {
  return String(value).padStart(2, "0")
}

/** `mm:ss`, or `h:mm:ss` past an hour — the Mac's `durationLabel`. */
export function durationLabel(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds))
  const hours = Math.floor(whole / 3600)
  const minutes = Math.floor((whole % 3600) / 60)
  const rest = whole % 60
  return hours > 0 ? `${String(hours)}:${pad(minutes)}:${pad(rest)}` : `${pad(minutes)}:${pad(rest)}`
}

/**
 * Where the elapsed clock is now.
 *
 * The clock counts *recording*, not wall time: a recording paused for a minute
 * has not gained a minute of video, and a timer that said otherwise would
 * disagree with the file. `baseSeconds` is what the daemon last reported, and
 * `runningSince` is when this side last saw it start counting.
 */
export function elapsedSeconds(
  baseSeconds: number,
  runningSince: number | null,
  now: number,
): number {
  if (runningSince === null) return baseSeconds
  return baseSeconds + Math.max(0, (now - runningSince) / 1000)
}

/**
 * Whether a time limit has been reached.
 *
 * Zero is unlimited, so it never fires — the check is separate from the
 * comparison because "0 seconds elapsed of a 0 second limit" is otherwise true
 * the instant recording starts.
 */
export function reachedTimeLimit(elapsed: number, limitSeconds: number): boolean {
  return limitSeconds > 0 && elapsed >= limitSeconds
}

/** The file name a saved recording takes — `recording_<stamp>.mp4` on the Mac. */
export function recordingFileName(at: Date): string {
  const stamp =
    `${String(at.getFullYear())}${pad(at.getMonth() + 1)}${pad(at.getDate())}` +
    `_${pad(at.getHours())}${pad(at.getMinutes())}${pad(at.getSeconds())}`
  return `recording_${stamp}.mp4`
}

/** `2.1 MB` — the size a finished recording reports. */
export function fileSizeLabel(bytes: number): string {
  if (bytes < 1024) return `${String(bytes)} B`
  if (bytes < 1_048_576) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / 1_048_576).toFixed(1)} MB`
}
