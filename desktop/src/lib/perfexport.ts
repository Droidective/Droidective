import { asDaemonError, exportText } from "@/lib/daemon"
import type { ToastInput } from "@/lib/notifications"
import { toCsv, toJson, type TimedSample } from "@/lib/performance"

/**
 * Writes the recording as JSON *and* CSV, which is the Mac's export.
 *
 * Both formats, always: the CSV is for a spreadsheet and the JSON keeps the
 * per-process rows a CSV row cannot hold.
 */
export async function writeRecording(
  samples: readonly TimedSample[],
  context: { serial: string; packageId: string | null },
): Promise<ToastInput> {
  if (samples.length === 0) return { ok: false, message: "There was nothing to export." }
  const stem = `performance_${context.serial.replaceAll(/[^\w.-]/gu, "_")}`
  try {
    await exportText(`${stem}.json`, toJson(samples, context))
    const csv = await exportText(`${stem}.csv`, toCsv(samples))
    return {
      ok: true,
      message: `Exported ${String(samples.length)} samples (JSON + CSV)`,
      revealPath: csv,
    }
  } catch (thrown) {
    return { ok: false, message: asDaemonError(thrown).message }
  }
}
