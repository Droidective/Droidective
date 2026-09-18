import { AboutPane } from "@/components/AboutPane"
import { CatalogPane } from "@/components/CatalogPane"
import type { FeaturePaneProps } from "@/components/FeaturePane"
import { HomeView } from "@/components/HomeView"
import { ABOUT_TAB, CATALOG_TAB, HOME_TAB } from "@/lib/layout"

/**
 * The app's own screens, opened from the sidebar footer rather than the
 * registry. No daemon serves them, so they are matched before the lookup.
 */
export function chromePane(props: FeaturePaneProps) {
  if (props.id === HOME_TAB) {
    return (
      <HomeView
        features={props.features}
        sidebarOrder={props.sidebarOrder}
        categoryOrder={props.categoryOrder}
        favorites={props.favorites}
        onOpen={props.onOpen}
      />
    )
  }
  if (props.id === CATALOG_TAB) {
    return (
      <CatalogPane
        features={props.features}
        disabled={props.disabledFeatures}
        sidebarOrder={props.sidebarOrder}
        categoryOrder={props.categoryOrder}
        onSetEnabled={props.onSetEnabled}
        onSetGroupEnabled={props.onSetGroupEnabled}
      />
    )
  }
  if (props.id === ABOUT_TAB) return <AboutPane />
  return null
}
