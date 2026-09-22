import { useEffect } from "react"

import { Button } from "@/components/Controls"
import { SandboxPane } from "@/components/SandboxPane"
import type { Device } from "@/lib/wire"

/**
 * An app's private files, over the list — the Mac's `showFiles` sheet.
 *
 * The Sandbox Browser itself, handed the package rather than asked for one, so
 * there is one implementation of `run-as` and its not-debuggable state.
 */
export function AppFilesSheet({
  device,
  packageId,
  onDone,
}: {
  device: Device | null
  packageId: string
  onDone: () => void
}) {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onDone()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onDone])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      <button type="button" aria-label="Done" onClick={onDone} className="absolute inset-0 cursor-default" />
      <dialog
        open
        aria-modal="true"
        aria-label={`Files · ${packageId}`}
        className="relative flex h-[460px] w-[580px] max-w-full flex-col overflow-hidden rounded-xl border border-border-subtle bg-bg-raised shadow-2xl"
      >
        <header className="flex shrink-0 items-center gap-3 border-b border-border-subtle px-3 py-2.5">
          <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-text-primary">
            Files · {packageId}
          </span>
          <Button onClick={onDone}>Done</Button>
        </header>
        <div className="min-h-0 flex-1">
          <SandboxPane device={device} packageId={packageId} />
        </div>
      </dialog>
    </div>
  )
}
