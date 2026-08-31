import { PackageOpen } from "lucide-react"

import { classifyDrop, type DropContext } from "@/lib/file-drop"

/**
 * What a drop is about to do, while the file is over the window.
 *
 * The Mac's drop zones highlight and say what they take; here the whole window
 * is the target, so the overlay is where that is said. It answers *before* the
 * drop rather than after, because "Connect a device first" is much more useful
 * as a reason not to let go than as an error afterwards.
 */
export function FileDropOverlay({
  over,
  busy,
  context,
}: {
  over: boolean
  busy: boolean
  context: DropContext
}) {
  if (!over && !busy) return null

  // The paths are not known until the drop — the browser hides them during a
  // drag — so the message is about *where* it would go, not what it is.
  const destination = classifyDrop(["probe.bin"], context)
  const line =
    destination.kind === "ignore"
      ? destination.reason
      : `Drop to push into ${destination.kind === "push" ? destination.destination : "the device"}`

  return (
    <div className="pointer-events-none fixed inset-0 z-[60] flex items-center justify-center bg-black/50">
      <div className="flex flex-col items-center gap-2 rounded-xl border-2 border-dashed border-accent bg-bg-raised px-8 py-6 text-center">
        <PackageOpen size={28} className="text-accent" />
        <p className="text-[14px] text-text-primary">
          {busy ? "Reading the dropped file…" : "Drop to install an APK or app bundle"}
        </p>
        <p className="max-w-sm text-[12px] text-text-secondary">{busy ? "" : line}</p>
      </div>
    </div>
  )
}
