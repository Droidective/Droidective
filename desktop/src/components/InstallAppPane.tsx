import { useState } from "react"
import { CheckCircle2, Download, XCircle } from "lucide-react"
import { Button } from "@/components/Controls"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, pickAndInstall } from "@/lib/daemon"
import type { Device, InstallOutcome } from "@/lib/wire"

/**
 * Install an app package — the Mac's `InstallAppView`.
 *
 * The same drop-zone shape and the same four formats, with one difference the
 * port cannot hide: **there is no drag and drop yet**. A file dragged onto a
 * webview arrives as a `File` with no path, and the daemon needs a real one;
 * `dragDropEnabled: false` is also what makes the tab drags work at all, so
 * the two have to be made to coexist (backlog 17). The zone says so rather
 * than looking droppable and silently doing nothing.
 *
 * It installs onto the selected device. The Mac installs onto every targeted
 * one when run-on-all is set, but this app's device bar selects a single
 * device — run-on-all is part of the device-bar work (backlog 6), and the
 * route already takes a list for when it lands.
 */
export function InstallAppPane({ device }: { device: Device | null }) {
  const { show } = useNotifications()
  const [installing, setInstalling] = useState(false)
  const [outcomes, setOutcomes] = useState<InstallOutcome[]>([])
  const [fileName, setFileName] = useState<string | null>(null)

  const serials = device === null ? [] : [device.serial]

  const choose = () => {
    if (serials.length === 0) {
      show({ ok: false, message: "Connect a device first" })
      return
    }
    setInstalling(true)
    void (async () => {
      try {
        const response = await pickAndInstall(serials)
        // Null means the picker was dismissed. Nothing happened, so nothing
        // is reported — a toast there would be noise for a deliberate act.
        if (response === null) return
        setOutcomes(response.outcomes)
        setFileName(response.fileName)
        const failed = response.outcomes.filter((outcome) => !outcome.ok)
        show(
          failed.length === 0
            ? { ok: true, message: `Installed ${response.fileName}` }
            : { ok: false, message: `${response.fileName} — ${failed[0]?.message ?? "failed"}` },
        )
      } catch (thrown) {
        show({ ok: false, message: asDaemonError(thrown).message })
      } finally {
        setInstalling(false)
      }
    })()
  }

  return (
    <div className="flex h-full flex-col items-center gap-4 overflow-y-auto p-6">
      <div className="flex w-full max-w-[560px] flex-col items-center gap-3 rounded-[14px] border border-dashed border-border-subtle bg-bg-surface px-6 py-10">
        <Download size={40} className="text-accent" />
        <p className="text-[17px] font-medium text-text-primary">
          {installing ? "Installing…" : "Choose an app package"}
        </p>
        <p className="text-[11.5px] text-text-tertiary">APK · APKS · XAPK · APKM</p>
        <Button tone="primary" onClick={choose} disabled={installing}>
          Choose File…
        </Button>
        <p className="max-w-sm text-center text-[11.5px] text-text-tertiary">
          Drag and drop is not wired up here yet — a dragged file reaches the window without a
          path.
        </p>
      </div>

      {outcomes.length === 0 ? null : (
        <div className="flex w-full max-w-[560px] flex-col gap-1.5">
          {fileName === null ? null : (
            <p className="text-[11.5px] text-text-tertiary">{fileName}</p>
          )}
          {outcomes.map((outcome) => (
            <div
              key={outcome.serial}
              className="flex items-start gap-2 rounded-md bg-bg-surface px-3 py-2"
            >
              {outcome.ok ? (
                <CheckCircle2 size={14} className="mt-0.5 shrink-0 text-accent" />
              ) : (
                <XCircle size={14} className="mt-0.5 shrink-0 text-danger" />
              )}
              <div className="min-w-0">
                <p className="text-text-primary">{outcome.serial}</p>
                <p className="break-words text-[11.5px] text-text-tertiary" data-selectable>
                  {outcome.message}
                </p>
              </div>
            </div>
          ))}
        </div>
      )}

      <p className="text-[11.5px] text-text-tertiary">
        {device === null ? "Connect a device to install onto" : `Installs on ${device.label}`}
      </p>
    </div>
  )
}
