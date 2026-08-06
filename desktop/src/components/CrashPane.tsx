import { useState } from "react"
import { ConfirmDialog } from "@/components/ConfirmDialog"
import { CrashDetail } from "@/components/CrashDetail"
import { CrashList } from "@/components/CrashList"
import { CrashNotices, CrashToolbar } from "@/components/CrashToolbar"
import { useCrashes, type Crashes } from "@/hooks/useCrashes"
import { formatCrash, type CrashFormat } from "@/lib/crashes"
import { asDaemonError, copyText, exportText } from "@/lib/daemon"
import type { Device } from "@/lib/wire"

/**
 * Every crash the device recorded — the Mac's Crash Catcher.
 *
 * The daemon reads the crash buffer, falls back to the main buffer when it is
 * empty, and splits the result with `CrashParser`; none of that is re-decided
 * here. What this screen owns is narrowing the list and getting one crash out
 * of the app, and those rules live in `lib/crashes.ts`.
 */
export function CrashPane({ device }: { device: Device | null }) {
  const crashes = useCrashes(device?.serial ?? null)
  const [showRaw, setShowRaw] = useState(false)
  const [confirmingClear, setConfirmingClear] = useState(false)
  const [action, setAction] = useState<{ ok: boolean; message: string; path?: string } | null>(null)

  if (!device) {
    return <p className="p-6 text-text-tertiary">Connect a device to catch crashes.</p>
  }

  const block = () => {
    const crash = crashes.selected
    if (crash === null) return ""
    return showRaw ? crash.raw : crash.body
  }

  const copy = (format: CrashFormat) => {
    setAction(null)
    copyText(formatCrash(block(), format)).then(
      () => {
        setAction({ ok: true, message: "Copied the crash to the clipboard." })
      },
      (thrown: unknown) => {
        setAction({ ok: false, message: asDaemonError(thrown).message })
      },
    )
  }

  const save = () => {
    const crash = crashes.selected
    if (crash === null) return
    setAction(null)
    exportText(fileName(crash.kind, device.serial), block()).then(
      (path) => {
        setAction({ ok: true, message: `Saved to ${path}`, path })
      },
      (thrown: unknown) => {
        setAction({ ok: false, message: asDaemonError(thrown).message })
      },
    )
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <CrashToolbar
        crashes={crashes.visible}
        filters={crashes.filters}
        onFilters={crashes.setFilters}
        loading={crashes.loading}
        watching={crashes.watching}
        onWatching={crashes.setWatching}
        onRefresh={crashes.refresh}
        selected={crashes.selected}
        onCopy={copy}
        onSave={save}
        onClear={() => {
          setConfirmingClear(true)
        }}
      />

      {confirmingClear ? (
        <ConfirmDialog
          title="Clear the device's crash buffer?"
          message="Removes every recorded crash from the device (logcat -c -b crash). This can't be undone."
          confirmLabel="Clear Buffer"
          onConfirm={() => {
            setConfirmingClear(false)
            crashes.clear()
          }}
          onCancel={() => {
            setConfirmingClear(false)
          }}
        />
      ) : null}

      <CrashNotices
        crashes={crashes}
        action={action}
        onDismissAction={() => {
          setAction(null)
        }}
      />

      <Body crashes={crashes} showRaw={showRaw} onShowRaw={setShowRaw} />
    </div>
  )
}

/** The list and the trace, or the reason there is neither. */
function Body({
  crashes,
  showRaw,
  onShowRaw,
}: {
  crashes: Crashes
  showRaw: boolean
  onShowRaw: (on: boolean) => void
}) {
  if (crashes.phase === "checking") {
    return <Filler>Reading the device’s crash buffer…</Filler>
  }
  if (crashes.phase === "failed" && crashes.visible.length === 0) {
    return (
      <Filler>
        Couldn’t read crashes. Check the connection, then refresh.
      </Filler>
    )
  }
  if (crashes.shown.length === 0) {
    return (
      <Filler>
        {crashes.visible.length === 0
          ? "No crashes detected. Turn on Watch to be told when something crashes."
          : "No crash matches those filters."}
      </Filler>
    )
  }
  return (
    <div className="flex min-h-0 flex-1">
      <CrashList crashes={crashes.shown} selected={crashes.selected?.id ?? null} onSelect={crashes.select} />
      {crashes.selected === null ? (
        <Filler>Pick a crash to inspect its trace.</Filler>
      ) : (
        <CrashDetail crash={crashes.selected} showRaw={showRaw} onShowRaw={onShowRaw} />
      )}
    </div>
  )
}

function Filler({ children }: { children: string }) {
  return (
    <p className="flex min-h-0 flex-1 items-center justify-center px-8 text-center text-text-tertiary">
      {children}
    </p>
  )
}

/** `export_text` checks this name, but building a safe one here is cheaper. */
function fileName(kind: string, serial: string): string {
  return `crash_${kind}_${serial.replaceAll(/[^\w.-]/gu, "_")}.txt`
}
