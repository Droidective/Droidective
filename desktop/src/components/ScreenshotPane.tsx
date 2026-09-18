import { Camera } from "lucide-react"
import { useCallback, useState } from "react"
import { Button } from "@/components/Controls"
import { NoDevice } from "@/components/NoDevice"
import { ScreenshotEditor } from "@/components/ScreenshotEditor"
import { useNotifications } from "@/hooks/useNotifications"
import { useScreenshotEditor } from "@/hooks/useScreenshotEditor"
import { asDaemonError, captureScreenshot } from "@/lib/daemon"
import type { Device } from "@/lib/wire"

/** The Mac's delay picker, its four choices in its order. */
const DELAYS = [0, 3, 5, 10]

/**
 * Capture the device screen and mark it up — the Mac's `ScreenshotView`.
 *
 * The `screenshot` feature is an instant action in the registry and stays one:
 * a hotkey still grabs and saves with no dialog, exactly as the Mac's quick
 * paths do. Opening it as a tab is the other half, and it is this editor.
 */
export function ScreenshotPane({ device }: { device: Device | null }) {
  const editor = useScreenshotEditor()
  const [delay, setDelay] = useState(0)
  const [capturing, setCapturing] = useState(false)
  const { show } = useNotifications()

  const capture = useCallback(() => {
    if (device === null) return
    setCapturing(true)
    void captureScreenshot(device.serial, delay)
      .then(async (answer) => {
        const bytes = Uint8Array.from(globalThis.atob(answer.png), (c) => c.codePointAt(0) ?? 0)
        const bitmap = await createImageBitmap(new Blob([bytes], { type: "image/png" }))
        editor.open(bitmap)
      })
      .catch((thrown: unknown) => {
        show({ message: asDaemonError(thrown).message, ok: false })
      })
      .finally(() => {
        setCapturing(false)
      })
  }, [delay, device, editor, show])

  if (editor.image !== null) {
    return <ScreenshotEditor editor={editor} onNew={editor.close} />
  }
  if (device === null) return <NoDevice feature="screenshot" title="Screenshot" />

  return (
    <div className="flex h-full flex-col items-center justify-center gap-5 p-6 text-center">
      <div className="flex flex-col items-center gap-2.5">
        <Camera size={42} className="text-text-tertiary" />
        <h2 className="text-[17px] font-semibold text-text-primary">Capture a screenshot</h2>
        <p className="max-w-md whitespace-pre-line text-text-secondary">
          {"Grab the device screen, then mark it up, crop, and save —\nnothing is written to disk until you choose to."}
        </p>
      </div>

      <div className="flex items-center gap-4">
        <select
          aria-label="Delay"
          value={String(delay)}
          onChange={(event) => {
            setDelay(Number(event.target.value))
          }}
          className="rounded-md border border-border-subtle bg-bg-root px-2 py-1.5 text-[13px] text-text-primary outline-none focus:border-accent"
        >
          {DELAYS.map((seconds) => (
            <option key={seconds} value={String(seconds)}>
              {seconds === 0 ? "No delay" : `${seconds}s`}
            </option>
          ))}
        </select>
        <Button tone="primary" disabled={capturing} onClick={capture}>
          <span className="inline-flex min-w-[130px] items-center justify-center gap-1.5">
            <Camera size={13} />
            {capturing ? "Capturing…" : "Capture"}
          </span>
        </Button>
      </div>
    </div>
  )
}
