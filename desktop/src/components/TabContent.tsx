import { FeaturePane } from "@/components/FeaturePane"
import { cn } from "@/lib/cn"
import type { TabState } from "@/lib/tabs"
import type { Device, FeatureSummary } from "@/lib/wire"

export interface TabContentProps {
  tabs: TabState
  features: FeatureSummary[]
  featureByID: (id: string) => FeatureSummary | null
  device: Device | null
  packageId: string | null
  onSelectPackage: (packageId: string | null) => void
  onOpen: (id: string) => void
  sidebarOrder: string[]
  categoryOrder: string[]
}

/**
 * The body below the tab strip.
 *
 * Every open tab stays mounted and the inactive ones are hidden, not
 * unmounted: a tab that re-read the app list or dropped its log stream every
 * time you looked away would not be a tab. It is also why the app list stopped
 * re-fetching on each switch.
 */
export function TabContent(props: TabContentProps) {
  return (
    <>
      {props.tabs.openTabs.map((id) => (
        <div
          key={id}
          className={cn(
            "min-h-0 flex-1",
            id === props.tabs.activeTab ? "flex flex-col bg-bg-root" : "hidden",
          )}
        >
          <FeaturePane
            id={id}
            feature={props.featureByID(id)}
            features={props.features}
            device={props.device}
            packageId={props.packageId}
            onSelectPackage={props.onSelectPackage}
            onOpen={props.onOpen}
            sidebarOrder={props.sidebarOrder}
            categoryOrder={props.categoryOrder}
          />
        </div>
      ))}
    </>
  )
}
