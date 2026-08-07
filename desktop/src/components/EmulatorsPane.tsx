import { useCallback, useEffect, useState } from "react"
import { MonitorPlay, MonitorSmartphone, RefreshCw } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { IconButton } from "@/components/Hub"
import { ConfirmDialog } from "@/components/screen"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, emulatorAction, emulators } from "@/lib/daemon"
import type { Avd, DaemonError, EmulatorAction } from "@/lib/wire"

/**
 * Android emulators — the Mac's `EmulatorsView`.
 *
 * Its iOS Simulators section is deliberately absent: those are `xcrun simctl`
 * against an Apple toolchain, one of the two things the port genuinely cannot
 * carry. A running AVD offers Relaunch and Stop; a stopped one offers Launch
 * with Cold Boot and Wipe Data behind a ⋯ menu, which is exactly where the Mac
 * puts them.
 */
export function EmulatorsPane() {
  const { show } = useNotifications()
  const [avds, setAvds] = useState<Avd[] | null>(null)
  const [installed, setInstalled] = useState(true)
  const [error, setError] = useState<DaemonError | null>(null)
  const [busy, setBusy] = useState(false)
  const [wiping, setWiping] = useState<Avd | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      const response = await emulators()
      setAvds(response.avds)
      setInstalled(response.installed)
    } catch (thrown) {
      setError(asDaemonError(thrown))
      setAvds([])
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const run = (action: EmulatorAction, avd: Avd) => {
    setBusy(true)
    void (async () => {
      try {
        const result = await emulatorAction({
          action,
          avd: avd.name,
          ...(avd.runningSerial === null ? {} : { serial: avd.runningSerial }),
        })
        show({ ok: result.ok, message: result.message })
      } catch (thrown) {
        show({ ok: false, message: asDaemonError(thrown).message })
      } finally {
        setBusy(false)
        // An emulator takes time to appear or go; the list is re-read so the
        // row's buttons match what is actually running rather than what was
        // just asked for.
        await load()
      }
    })()
  }

  if (!installed) return <NotInstalled />

  return (
    <div className="flex h-full flex-col">
      <header className="flex shrink-0 items-center gap-2 border-b border-border-subtle bg-bg-chrome px-3 py-2">
        <h2 className="flex-1 text-[13px] text-text-primary">Android emulators</h2>
        <IconButton
          icon={<RefreshCw size={13} />}
          label="Refresh"
          onClick={() => {
            void load()
          }}
          disabled={busy}
        />
      </header>

      {error === null ? null : (
        <div className="p-3">
          <Banner tone="error">{error.message}</Banner>
        </div>
      )}

      <AvdList
        avds={avds}
        busy={busy}
        onRun={run}
        onWipe={setWiping}
      />

      {wiping === null ? null : (
        <ConfirmDialog
          title={`Wipe all data on ${wiping.displayName}? Apps, accounts, settings, and snapshots on the AVD are erased.`}
          confirmLabel="Wipe Data"
          onConfirm={() => {
            const target = wiping
            setWiping(null)
            run("wipeData", target)
          }}
          onCancel={() => {
            setWiping(null)
          }}
        />
      )}
    </div>
  )
}

/** Reading, empty, or the rows — the screen's three states. */
function AvdList({
  avds,
  busy,
  onRun,
  onWipe,
}: {
  avds: Avd[] | null
  busy: boolean
  onRun: (action: EmulatorAction, avd: Avd) => void
  onWipe: (avd: Avd) => void
}) {
  if (avds === null) return <p className="p-5 text-text-tertiary">Reading AVDs…</p>
  if (avds.length === 0) {
    return (
      <p className="flex min-h-0 flex-1 items-center justify-center px-8 text-center text-text-tertiary">
        No AVDs yet. Create one in Android Studio&rsquo;s Device Manager.
      </p>
    )
  }
  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      {avds.map((avd) => (
        <Row
          key={avd.name}
          avd={avd}
          busy={busy}
          onRun={(action) => {
            onRun(action, avd)
          }}
          onWipe={() => {
            onWipe(avd)
          }}
        />
      ))}
    </div>
  )
}

function Row({
  avd,
  busy,
  onRun,
  onWipe,
}: {
  avd: Avd
  busy: boolean
  onRun: (action: EmulatorAction) => void
  onWipe: () => void
}) {
  const running = avd.runningSerial !== null
  return (
    <div className="flex items-center gap-2.5 border-b border-border-subtle/50 px-3 py-2">
      <MonitorPlay
        size={16}
        className={running ? "shrink-0 text-accent" : "shrink-0 text-text-tertiary"}
      />
      <div className="min-w-0 flex-1">
        <p className="text-text-primary">{avd.displayName}</p>
        {running ? (
          <p className="text-[11.5px] text-accent">Running — {avd.runningSerial}</p>
        ) : null}
      </div>

      {running ? (
        <>
          <Button
            disabled={busy}
            title="Stop the emulator and boot it again"
            onClick={() => {
              onRun("relaunch")
            }}
          >
            Relaunch
          </Button>
          <Button
            disabled={busy}
            onClick={() => {
              onRun("stop")
            }}
          >
            Stop
          </Button>
        </>
      ) : (
        <>
          <Button
            tone="primary"
            disabled={busy}
            onClick={() => {
              onRun("launch")
            }}
          >
            Launch
          </Button>
          <MoreMenu
            disabled={busy}
            onColdBoot={() => {
              onRun("coldBoot")
            }}
            onWipe={onWipe}
          />
        </>
      )}
    </div>
  )
}

/** The Mac's ⋯ menu: Cold Boot, and Wipe Data behind a confirmation. */
function MoreMenu({
  disabled,
  onColdBoot,
  onWipe,
}: {
  disabled: boolean
  onColdBoot: () => void
  onWipe: () => void
}) {
  const [open, setOpen] = useState(false)
  return (
    <span className="relative">
      <IconButton
        icon={<span className="px-0.5 text-[15px] leading-none">⋯</span>}
        label="More"
        disabled={disabled}
        onClick={() => {
          setOpen((current) => !current)
        }}
      />
      {open ? (
        <>
          <button
            type="button"
            aria-label="Dismiss menu"
            onClick={() => {
              setOpen(false)
            }}
            className="fixed inset-0 z-40 cursor-default"
          />
          <span className="absolute right-0 z-50 mt-1 flex w-[190px] flex-col rounded-md border border-border-subtle bg-bg-raised py-1 shadow-xl">
            <button
              type="button"
              onClick={() => {
                setOpen(false)
                onColdBoot()
              }}
              className="px-3 py-1 text-left text-text-primary hover:bg-white/[0.08]"
            >
              Cold Boot (skip snapshot)
            </button>
            <button
              type="button"
              onClick={() => {
                setOpen(false)
                onWipe()
              }}
              className="px-3 py-1 text-left text-danger hover:bg-white/[0.08]"
            >
              Wipe Data…
            </button>
          </span>
        </>
      ) : null}
    </span>
  )
}

function NotInstalled() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
      <MonitorSmartphone size={26} className="text-text-tertiary" />
      <h2 className="text-[15px] font-medium text-text-primary">No emulator installed</h2>
      <p className="max-w-sm text-text-secondary">
        Install it through Android Studio&rsquo;s SDK Manager. Droidective never installs a tool
        itself.
      </p>
    </div>
  )
}
