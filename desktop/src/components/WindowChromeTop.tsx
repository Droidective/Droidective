import { Banner } from "@/components/Controls"
import { DeviceBarHost } from "@/components/DeviceBarHost"
import { PullProgressStrip } from "@/components/PullProgressStrip"
import type { Session } from "@/hooks/useSession"

/**
 * Everything above the workspace: the device bar, the daemon's error if there
 * is one, and the pull progress strip.
 *
 * One component because all three are the *window's* rather than any screen's
 * — the Mac keeps the same three in `RootView` above its detail pane, and the
 * strip in particular has to outlive the tab a pull was started from.
 */
export function WindowChromeTop({
  session,
  workspace,
  focusedFeature,
  sidebar,
  packageId,
  onSelectPackage,
}: {
  session: Session
  workspace: Parameters<typeof DeviceBarHost>[0]["workspace"]
  focusedFeature: Parameters<typeof DeviceBarHost>[0]["focusedFeature"]
  sidebar: Parameters<typeof DeviceBarHost>[0]["sidebar"]
  packageId: string | null
  onSelectPackage: (packageId: string | null) => void
}) {
  return (
    <>
      <DeviceBarHost
        session={session}
        workspace={workspace}
        focusedFeature={focusedFeature}
        sidebar={sidebar}
        packageId={packageId}
        onSelectPackage={onSelectPackage}
      />
      {session.error ? (
        <div className="px-3 pt-3">
          <Banner tone="error">{session.error.message}</Banner>
        </div>
      ) : null}
      <PullProgressStrip />
    </>
  )
}
