import { useState } from "react"
import { Camera, CheckCircle2, FileArchive, Info, Package, ScrollText } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { NoDevice } from "@/components/screen"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, createBugReport, revealPath } from "@/lib/daemon"
import { cn } from "@/lib/cn"
import type { Device } from "@/lib/wire"

/**
 * Bug Report — the Mac's `BugReportView`: say what goes in the zip, build it,
 * and offer to show it.
 *
 * "What's included" is four rows rather than a sentence for the reason the Mac
 * lists them: the zip goes into a ticket someone else reads, and knowing a
 * screenshot of the current screen is in it changes what you do before pressing
 * the button.
 */
export function BugReportPane({
  device,
  packageId,
}: {
  device: Device | null
  packageId: string | null
}) {
  const { show } = useNotifications()
  const [running, setRunning] = useState(false)
  const [saved, setSaved] = useState<string | null>(null)

  const generate = () => {
    if (device === null) return
    setRunning(true)
    setSaved(null)
    void (async () => {
      try {
        const response = await createBugReport(device.serial, packageId)
        setSaved(response.path)
        show({ message: "Bug report saved", ok: true, revealPath: response.path })
      } catch (thrown) {
        show({ message: asDaemonError(thrown).message, ok: false })
      } finally {
        setRunning(false)
      }
    })()
  }

  if (!device) return <NoDevice feature="bug-report" title="Bug Report" />

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <div className="mx-auto flex w-full max-w-[560px] flex-col gap-4 p-4">
        <section className="flex flex-col gap-2">
          <header>
            <h2 className="text-[15px] font-medium text-text-primary">What&rsquo;s included</h2>
            <p className="text-text-tertiary">
              A single zip you can drop straight into a bug ticket.
            </p>
          </header>
          <div className="overflow-hidden rounded-lg bg-bg-surface">
            <Included icon={Camera} title="Screenshot" detail="The current screen" first />
            <Included icon={ScrollText} title="Logcat" detail="The last 2,000 log lines" />
            <Included
              icon={Info}
              title="Device info"
              detail="Model, Android version, ABI, serial"
            />
            <Included
              icon={Package}
              title="App version"
              detail={
                packageId === null
                  ? "Pick an app in Apps to include it"
                  : `Included for ${packageId}`
              }
            />
          </div>
        </section>

        <section className="flex flex-col gap-2.5">
          <h2 className="text-[15px] font-medium text-text-primary">Generate</h2>
          <div>
            <Button tone="primary" disabled={running} onClick={generate}>
              <span className="flex items-center gap-1.5">
                <FileArchive size={13} />
                {running ? "Collecting…" : "Generate bug report"}
              </span>
            </Button>
          </div>
          {running ? (
            <p className="text-text-tertiary">
              Collecting screenshot, logs, and device info…
            </p>
          ) : null}
          {saved === null ? null : (
            <Banner tone="ok">
              <span className="flex items-center gap-2">
                <CheckCircle2 size={14} className="shrink-0 text-accent" />
                <span className="min-w-0 flex-1">
                  <span className="block">Bug report saved</span>
                  <span className="block text-[11.5px] opacity-70" data-selectable>
                    {saved}
                  </span>
                </span>
                <Button
                  onClick={() => {
                    void revealPath(saved)
                  }}
                >
                  Show in folder
                </Button>
              </span>
            </Banner>
          )}
        </section>
      </div>
    </div>
  )
}

function Included({
  icon: Icon,
  title,
  detail,
  first = false,
}: {
  icon: typeof Camera
  title: string
  detail: string
  first?: boolean
}) {
  return (
    <div
      className={cn(
        "flex items-start gap-3 px-3 py-2",
        first ? "" : "border-t border-border-subtle",
      )}
    >
      <Icon size={14} className="mt-0.5 shrink-0 text-text-tertiary" />
      <div className="min-w-0">
        <p className="text-text-primary">{title}</p>
        <p className="text-[11.5px] text-text-tertiary">{detail}</p>
      </div>
    </div>
  )
}
