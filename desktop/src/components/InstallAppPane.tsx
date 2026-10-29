import { useRef, useState } from "react"
import { Download } from "lucide-react"
import { Button } from "@/components/Controls"
import { PackageDetailsCard } from "@/components/PackageDetailsCard"
import { useNotifications } from "@/hooks/useNotifications"
import { useTargets } from "@/hooks/useTargets"
import { APK_STUDIO_ID, openInStudio } from "@/lib/apk-studio"
import { asDaemonError, installPath, packageDetails, pickPackage } from "@/lib/daemon"
import {
  installHeadline,
  openFailure,
  opensInStudio,
  readOpensApp,
  writeOpensApp,
} from "@/lib/install-app"
import type { Device, InstallOutcome, PackageDetails } from "@/lib/wire"

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
 * It installs onto every targeted device, which with the bar's Run on all
 * switch off is the selected one — `install-app` is one of the four features
 * the registry marks `supportsRunAll`. The package gets the Mac's details card,
 * with each device's outcome in it, because installing onto three where one
 * is out of space is a partial success, not a single verdict.
 *
 * "Open after installing" is remembered as it was last left, as the Mac's
 * `installOpensApp` is, and a plain APK can go on to APK Studio from the card.
 */
export function InstallAppPane({
  device,
  onOpen,
}: {
  device: Device | null
  onOpen: (id: string) => void
}) {
  const { serials, runningOnAll } = useTargets()
  const [opensApp, setOpensApp] = useState(readOpensApp)
  const flow = useInstallFlow(serials, opensApp)

  return (
    <div className="flex h-full flex-col items-center gap-4 overflow-y-auto p-6">
      <div className="flex w-full max-w-[560px] flex-col items-center gap-3 rounded-[14px] border border-dashed border-border-subtle bg-bg-surface px-6 py-10">
        <Download size={40} className="text-accent" />
        <p className="text-[17px] font-medium text-text-primary">
          {flow.installing ? "Installing…" : "Choose an app package"}
        </p>
        <p className="text-[11.5px] text-text-tertiary">APK · APKS · XAPK · APKM</p>
        <Button tone="primary" onClick={flow.choose} disabled={flow.installing}>
          Choose File…
        </Button>
        <p className="max-w-sm text-center text-[11.5px] text-text-tertiary">
          Drag and drop is not wired up here yet — a dragged file reaches the window without a
          path.
        </p>
      </div>

      <div className="flex flex-col items-center gap-2">
        <OpensAppBox
          on={opensApp}
          onChange={(on) => {
            setOpensApp(on)
            writeOpensApp(on)
          }}
        />
        <p className="text-[11.5px] text-text-tertiary">
          {destination(device, serials, runningOnAll)}
        </p>
      </div>

      {flow.path === null ? null : (
        <PackageDetailsCard
          path={flow.path}
          details={flow.details}
          failed={flow.detailsFailed}
          outcomes={flow.outcomes}
        >
          {opensInStudio(flow.path) ? (
            <StudioButton path={flow.path} onOpen={onOpen} />
          ) : null}
        </PackageDetailsCard>
      )}
    </div>
  )
}

/**
 * Pick, then read the package and install it side by side — the card fills in
 * while the install runs, as the Mac's does.
 */
function useInstallFlow(serials: string[], opensApp: boolean) {
  const { show, notifyIfBackgrounded } = useNotifications()
  const [installing, setInstalling] = useState(false)
  const [path, setPath] = useState<string | null>(null)
  const [details, setDetails] = useState<PackageDetails | null>(null)
  const [detailsFailed, setDetailsFailed] = useState<string | null>(null)
  const [outcomes, setOutcomes] = useState<InstallOutcome[]>([])
  // The package the card is showing, so a slow answer for the last pick
  // cannot land on this one.
  const shown = useRef<string | null>(null)

  const describe = (picked: string) => {
    packageDetails(picked)
      .then((read) => {
        if (shown.current === picked) setDetails(read)
      })
      .catch((thrown: unknown) => {
        if (shown.current === picked) setDetailsFailed(asDaemonError(thrown).message)
      })
  }

  const install = async (picked: string) => {
    const response = await installPath(serials, picked, opensApp)
    if (shown.current === picked) setOutcomes(response.outcomes)
    const headline = installHeadline(response.fileName, response.outcomes, opensApp)
    show(headline)
    const reason = opensApp ? openFailure(response.outcomes) : null
    if (reason !== null) show({ ok: false, message: `Installed ${response.fileName}. ${reason}` })
    // The one thing an install is most likely to outlast: attention. An
    // `.xapk` is a minute of unpacking and pushing, and nobody watches it.
    // The Mac posts the same two titles from `installAPKs`.
    notifyIfBackgrounded(
      headline.ok ? "Install finished" : "Install failed",
      headline.message,
      !headline.ok,
    )
  }

  const choose = () => {
    if (serials.length === 0) {
      show({ ok: false, message: "Connect a device first" })
      return
    }
    void (async () => {
      try {
        const picked = await pickPackage()
        // Null means the picker was dismissed. Nothing happened, so nothing
        // is reported — a toast there would be noise for a deliberate act.
        if (picked === null) return
        shown.current = picked
        setPath(picked)
        setDetails(null)
        setDetailsFailed(null)
        setOutcomes([])
        describe(picked)
        setInstalling(true)
        await install(picked)
      } catch (thrown) {
        show({ ok: false, message: asDaemonError(thrown).message })
      } finally {
        setInstalling(false)
      }
    })()
  }

  return { installing, path, details, detailsFailed, outcomes, choose }
}

function OpensAppBox({ on, onChange }: { on: boolean; onChange: (on: boolean) => void }) {
  return (
    <label className="flex items-center gap-1.5 text-text-primary">
      <input
        type="checkbox"
        checked={on}
        onChange={(event) => {
          onChange(event.target.checked)
        }}
        className="accent-accent"
      />
      Open after installing
    </label>
  )
}

/** The Mac's `openInApkStudio`: hand the APK over, then show the studio. */
function StudioButton({ path, onOpen }: { path: string; onOpen: (id: string) => void }) {
  return (
    <div>
      <Button
        onClick={() => {
          openInStudio(path)
          onOpen(APK_STUDIO_ID)
        }}
      >
        Open in APK Studio
      </Button>
    </div>
  )
}

/** Where this is about to install, so a fan-out is never a surprise. */
function destination(device: Device | null, serials: string[], runningOnAll: boolean): string {
  if (serials.length === 0) return "Connect a device to install onto"
  if (runningOnAll && serials.length > 1) return `Installs on ${String(serials.length)} devices`
  return `Installs on ${device?.label ?? serials[0] ?? ""}`
}
