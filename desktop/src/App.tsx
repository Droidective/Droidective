import { useCallback, useEffect, useMemo, useState } from "react"
import { Banner } from "@/components/Controls"
import { DeviceBar } from "@/components/DeviceBar"
import { Sidebar } from "@/components/Sidebar"
import { TabContent } from "@/components/TabContent"
import { TabStrip } from "@/components/TabStrip"
import { useSession } from "@/hooks/useSession"
import { useTabShortcuts } from "@/hooks/useTabShortcuts"
import { useWorkspace } from "@/hooks/useWorkspace"
import { sidebarFeatures } from "@/lib/sidebar"

export function App() {
  const session = useSession()
  const features = useMemo(() => sidebarFeatures(session.features), [session.features])
  const workspace = useWorkspace(features)
  // Lifted out of the Apps pane: a `needsBundle` action needs the same choice,
  // so it cannot live inside one tab.
  const [packageId, setPackageId] = useState<string | null>(null)

  // A package id means nothing on a different device, so the choice is dropped
  // when the selection changes — here, where it is owned.
  const serial = session.selected?.serial ?? null
  useEffect(() => {
    setPackageId(null)
  }, [serial])

  const byID = useCallback(
    (id: string) => features.find((feature) => feature.id === id) ?? null,
    [features],
  )

  useTabShortcuts({
    activeTab: workspace.tabs.activeTab,
    onClose: workspace.close,
    onActivateIndex: workspace.activateIndex,
  })

  if (session.status.state === "starting") {
    return <Splash>Starting droidectived…</Splash>
  }
  if (session.status.state === "failed") {
    return (
      <Splash>
        <Banner tone="error">
          <strong>droidectived would not start.</strong>
          <div className="mt-1 opacity-80">{session.status.message}</div>
        </Banner>
      </Splash>
    )
  }

  return (
    <div className="flex h-full flex-col">
      <DeviceBar
        devices={session.devices}
        devicesLoaded={session.devicesLoaded}
        selected={session.selected}
        onSelect={session.select}
      />

      <div className="flex min-h-0 flex-1">
        <Sidebar
          features={features}
          activeID={workspace.tabs.activeTab}
          onOpen={workspace.open}
          sidebarOrder={workspace.layout.sidebarOrder}
          categoryOrder={workspace.layout.categoryOrder}
          collapsedCategories={workspace.layout.collapsedCategories}
          onSidebarOrder={workspace.setSidebarOrder}
          onCategoryOrder={workspace.setCategoryOrder}
          onToggleCollapsed={workspace.toggleCategory}
        />

        <div className="flex min-w-0 flex-1 flex-col">
          <TabStrip
            tabs={workspace.tabs}
            featureByID={byID}
            onSelect={workspace.open}
            onClose={workspace.close}
            onReorder={workspace.reorder}
          />

          {session.error ? (
            <div className="p-3">
              <Banner tone="error">{session.error.message}</Banner>
            </div>
          ) : null}

          <TabContent
            tabs={workspace.tabs}
            features={features}
            featureByID={byID}
            device={session.selected}
            packageId={packageId}
            onSelectPackage={setPackageId}
            onOpen={workspace.open}
            sidebarOrder={workspace.layout.sidebarOrder}
            categoryOrder={workspace.layout.categoryOrder}
          />
        </div>
      </div>
    </div>
  )
}

function Splash({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full items-center justify-center p-8">
      <div className="max-w-md text-center text-text-secondary">{children}</div>
    </div>
  )
}
