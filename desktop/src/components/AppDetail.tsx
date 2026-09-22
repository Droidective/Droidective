import { Boxes } from "lucide-react"

import { AppActions } from "@/components/AppActions"
import { AppPullButton } from "@/components/AppPullButton"
import { Button } from "@/components/Controls"
import type { AppActionDescriptor, AppSummary } from "@/lib/wire"

/** One app: what it is, and every verb the Mac offers for it. */
export function AppDetail({
  app,
  actions,
  serial,
  onFiles,
}: {
  app: AppSummary
  actions: AppActionDescriptor[]
  serial: string
  onFiles: () => void
}) {
  return (
    <div className="flex h-full flex-col gap-4 overflow-y-auto p-6">
      <header className="flex items-start gap-3">
        <Boxes size={22} className="mt-0.5 shrink-0 text-accent" />
        <div className="min-w-0">
          <h2 className="text-[17px] font-semibold text-text-primary" data-selectable>
            {app.displayName}
          </h2>
          <p className="mt-0.5 text-text-secondary" data-selectable>
            {app.packageId}
            {app.versionName === null ? "" : ` · ${app.versionName}`}
            {app.isSystem ? " · system app" : ""}
          </p>
        </div>
      </header>

      <AppActions actions={actions} packageId={app.packageId} serial={serial} />
      <div className="flex flex-wrap items-center gap-2">
        {/* Both of the Mac's, in its order. Pull APK is here as well as on App
            Info because this is the screen someone is on when they decide they
            want the file — walking to another screen to fetch the app already
            selected is the step worth not having. */}
        <AppPullButton serial={serial} packageId={app.packageId} />
        {/* Over this screen rather than away from it: the Sandbox Browser is a
            feature of its own here, and sending someone to its tab loses their
            place in a list that can run to thousands of rows. */}
        <Button
          onClick={() => {
            onFiles()
          }}
        >
          Explore files
        </Button>
      </div>
    </div>
  )
}
