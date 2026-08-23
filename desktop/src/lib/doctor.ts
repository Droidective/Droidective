import type { ToolReport } from "@/lib/wire"

/**
 * Which tools the Doctor reports on, and what a report adds up to.
 *
 * The daemon detects all four the registry knows about; only two are *checked*
 * here, matching the Mac's `DoctorSettingsView.checks`. scrcpy and ffmpeg are
 * absent for the same reason they are absent there — the Mac bundles its own, so
 * a missing system copy blocks nothing. That they are absent for a *different*
 * reason here (nothing is bundled yet, and the features that would need them
 * are not ported) is why the mirror's row will arrive with the mirror.
 */
export interface Check {
  id: string
  name: string
  purpose: string
}

export const CHECKS: readonly Check[] = [
  { id: "adb", name: "adb", purpose: "Required — powers every device action" },
  { id: "emulator", name: "emulator", purpose: "Launch & manage Android emulators" },
]

/** The checked tools, in the Doctor's order, paired with what was found. */
export function checkedTools(
  tools: readonly ToolReport[],
): { check: Check; report: ToolReport | null }[] {
  return CHECKS.map((check) => ({
    check,
    report: tools.find((tool) => tool.id === check.id) ?? null,
  }))
}

/** Checked tools that are missing — the ones that actually block something. */
export function blocking(tools: readonly ToolReport[]): ToolReport[] {
  return checkedTools(tools)
    .map((row) => row.report)
    .filter((report): report is ToolReport => report !== null && !report.installed)
}

/**
 * The one-line verdict.
 *
 * An empty report is "still looking", not "all set": claiming everything is
 * installed before anything has been checked is the one wrong answer here.
 */
export function verdict(
  tools: readonly ToolReport[],
): { tone: "pending" | "ok" | "warn"; message: string } {
  if (tools.length === 0) return { tone: "pending", message: "Checking your setup…" }
  const missing = blocking(tools)
  if (missing.length === 0) {
    return { tone: "ok", message: "All set — every required tool is installed." }
  }
  const count = missing.length
  return {
    tone: "warn",
    message: `${String(count)} tool${count === 1 ? "" : "s"} missing — some features won't work until installed.`,
  }
}

/**
 * Whether adb itself is missing, which the device bar warns about.
 *
 * Null while nothing has been checked: the bar must not flash a warning during
 * startup, when the honest answer is "not yet known".
 */
export function adbMissing(tools: readonly ToolReport[]): boolean | null {
  const adb = tools.find((tool) => tool.id === "adb")
  return adb === undefined ? null : !adb.installed
}
