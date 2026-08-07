import { asDaemonError, exportText } from "@/lib/daemon"
import { toCsv, toJson, type TimedNetSample } from "@/lib/netspeed"
import type { ToastInput } from "@/lib/notifications"

/**
 * Writes a network recording as JSON *and* CSV, which is the Mac's export.
 *
 * Both formats, always, for the reason the Performance export gives: the CSV
 * is for a spreadsheet and the JSON keeps the per-interface rows a CSV row
 * cannot hold.
 */
export async function writeRecording(
  samples: readonly TimedNetSample[],
  serial: string,
): Promise<ToastInput> {
  if (samples.length === 0) return { ok: false, message: "There was nothing to export." }
  const stem = `netspeed_${serial.replaceAll(/[^\w.-]/gu, "_")}`
  try {
    await exportText(`${stem}.json`, toJson(samples, serial))
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
