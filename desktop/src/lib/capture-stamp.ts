/**
 * `ScreenCaptureService.stamp()`'s format — `yyyy-MM-dd_HH-mm-ss` in local
 * time.
 *
 * Shared rather than written out per caller because it is a contract with the
 * Mac, not a convenience: a folder holding a screenshot from one app and a
 * console dump from the other sorts as one set only while both spell the stamp
 * the same way, and two copies of that spelling drift.
 */
function pad(value: number): string {
  return String(value).padStart(2, "0")
}

export function captureStamp(now: Date): string {
  return (
    `${String(now.getFullYear())}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}` +
    `_${pad(now.getHours())}-${pad(now.getMinutes())}-${pad(now.getSeconds())}`
  )
}
