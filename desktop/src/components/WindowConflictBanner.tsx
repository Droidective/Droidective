import { AppWindowMac } from "lucide-react"

import { Button } from "@/components/Controls"
import { windowTitle, type WindowClaim } from "@/lib/workspaces"

/**
 * "Another window is already using this" — the Mac's Focus / Take Over banner.
 *
 * Four features cannot run twice against one device: scrcpy and screen
 * recording share the device's one H.264 encoder, the JS console loses its CDP
 * target to whichever client connected last, and Frida owns a port. Rather
 * than let the second one race and silently kill the first, the second window
 * says who has it.
 *
 * **Take Over closes the tab in the owning window first.** That ordering is
 * the point of the button: starting here and hoping the other side notices is
 * exactly the moment with two live sessions that this exists to prevent.
 */
export function WindowConflictBanner({
  owner,
  featureTitle,
  onFocus,
  onTakeOver,
  busy,
}: {
  owner: WindowClaim
  featureTitle: string
  onFocus: () => void
  onTakeOver: () => void
  busy: boolean
}) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-3 p-8 text-center">
      <AppWindowMac size={26} className="text-text-tertiary" />
      <h2 className="text-[15px] font-medium text-text-primary">
        {windowTitle(owner.ordinal)} is using {featureTitle}
      </h2>
      <p className="max-w-sm text-text-secondary">
        This device can only run it in one window at a time. Go to that window, or take it over
        here — the tab there closes first, so the two never overlap.
      </p>
      <div className="flex gap-3">
        <Button onClick={onFocus}>
          <span className="w-[132px]">Focus {windowTitle(owner.ordinal)}</span>
        </Button>
        <Button tone="primary" onClick={onTakeOver} disabled={busy}>
          <span className="w-[132px]">{busy ? "Taking over…" : "Take Over Here"}</span>
        </Button>
      </div>
    </div>
  )
}
