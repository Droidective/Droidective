import { listen } from "@tauri-apps/api/event"
import { useEffect, useRef } from "react"
import type { TerminalCommands } from "@/hooks/useTerminalCommands"
import type { SidebarModeController } from "@/hooks/useSidebarMode"
import type { WorkspaceController } from "@/hooks/useWorkspace"
import { ABOUT_TAB, CATALOG_TAB } from "@/lib/layout"
import { LINKS, bugReportUrl, featureRequestUrl } from "@/lib/links"
import { openUrl } from "@/lib/daemon"
import { sidebarSections, visibleFeatures } from "@/lib/sidebar"
import type { FeatureSummary } from "@/lib/wire"

/** The event `src-tauri/src/menu.rs` forwards every click on. */
const MENU_EVENT = "menu://command"

/** The prefix a Go row's id carries, followed by its 0-based rank. */
const GO_PREFIX = "go.row-"

export interface MenuHandlers {
  workspace: WorkspaceController
  sidebar: SidebarModeController
  features: FeatureSummary[]
  /** The mounted Terminal pane, or null when it is not open. */
  terminal: { current: TerminalCommands | null }
  onPalette: () => void
  onSettings: () => void
  /** Opens the Terminal feature, for New Terminal with nothing open. */
  onOpenTerminal: () => void
}

/**
 * Runs the window menu's commands.
 *
 * The menu itself is native and lives in Rust (`src-tauri/src/menu.rs`), which
 * is the only place a webview's menu *can* live — but everything it acts on is
 * state up here, so Rust forwards the command id and this is where it happens.
 *
 * One listener over a dispatch table rather than a listener per item: the ids
 * come from one table on the Rust side, and `menu.test.ts` checks that every one
 * of them is answered here. Two lists that must agree, with a test that they do.
 */
export function useMenuCommands(handlers: MenuHandlers): void {
  // Read through a ref so the subscription is set up once. Re-subscribing on
  // every render would drop clicks in the gap between unlisten and listen.
  const latest = useRef(handlers)
  latest.current = handlers

  useEffect(() => {
    const pending = listen<string>(MENU_EVENT, (event) => {
      run(event.payload, latest.current)
    })
    return () => {
      void pending.then((unlisten) => {
        unlisten()
      }, ignore)
    }
  }, [])
}

/** Exported for the id-coverage test; not called from anywhere else. */
export function menuCommandIds(): readonly string[] {
  return Object.keys(TABLE)
}

/**
 * What each id does. A table so the coverage test can enumerate it — a `switch`
 * would need the test to parse this file instead of importing it.
 */
const TABLE: Record<string, (handlers: MenuHandlers) => void> = {
  "terminal.new": (handlers) => {
    const terminal = handlers.terminal.current
    // With nothing open, New Terminal *opens* the Terminal — which is what the
    // Mac's does, and why it is the one terminal command never greyed out.
    if (terminal === null) handlers.onOpenTerminal()
    else terminal.newTab()
  },
  "terminal.split-beside": (handlers) => handlers.terminal.current?.split("vertical"),
  "terminal.split-below": (handlers) => handlers.terminal.current?.split("horizontal"),
  "terminal.close": (handlers) => handlers.terminal.current?.closeFocused(),
  "terminal.rename": (handlers) => handlers.terminal.current?.renameFocused(),
  "terminal.next": (handlers) => handlers.terminal.current?.cycle(1),
  "terminal.previous": (handlers) => handlers.terminal.current?.cycle(-1),

  "app.find-feature": (handlers) => handlers.onPalette(),
  "app.catalog": (handlers) => handlers.workspace.open(CATALOG_TAB),
  "app.settings": (handlers) => handlers.onSettings(),
  "app.about": (handlers) => handlers.workspace.open(ABOUT_TAB),

  "view.toggle-sidebar": (handlers) => handlers.sidebar.toggle(),
  "view.zoom-in": (handlers) => handlers.workspace.zoom(1),
  "view.zoom-out": (handlers) => handlers.workspace.zoom(-1),
  "view.zoom-reset": (handlers) => handlers.workspace.zoom(0),

  // The Mac's New Tab opens the palette and the chosen feature lands in a tab.
  "tab.new": (handlers) => handlers.onPalette(),
  "tab.close": (handlers) => {
    const active = activeOf(handlers.workspace)
    if (active !== null) handlers.workspace.close(active)
  },
  "tab.next": (handlers) => handlers.workspace.cycleTab(1),
  "tab.previous": (handlers) => handlers.workspace.cycleTab(-1),

  // Opened in the browser, not a tab: these are the same four links About
  // shows, and `openUrl` is the one path the webview has to the outside.
  "help.report-issue": () => {
    void openUrl(bugReportUrl(null)).catch(ignore)
  },
  "help.request-feature": () => {
    void openUrl(featureRequestUrl()).catch(ignore)
  },
  "help.repository": () => {
    void openUrl(LINKS.repo).catch(ignore)
  },
  "help.releases": () => {
    void openUrl(LINKS.releases).catch(ignore)
  },
}

function run(id: string, handlers: MenuHandlers): void {
  const rank = goRank(id)
  if (rank !== null) {
    openSidebarRow(rank, handlers)
    return
  }
  // An id this build does not know is not worth a crash: a menu built by a
  // newer Rust binary than the bundled page is a real combination during
  // development, and dropping the click is the honest response.
  TABLE[id]?.(handlers)
}

/**
 * The 0-based rank in `go.row-N`, or null when the id is something else.
 *
 * The empty suffix is checked explicitly because `Number("")` is **0**, not
 * NaN — so `go.row-` would otherwise open the first sidebar row, and a
 * malformed id would look like a working command.
 */
export function goRank(id: string): number | null {
  if (!id.startsWith(GO_PREFIX)) return null
  const suffix = id.slice(GO_PREFIX.length)
  if (suffix.length === 0) return null
  const rank = Number(suffix)
  return Number.isInteger(rank) && rank >= 0 ? rank : null
}

/**
 * Opens the Nth row the sidebar is showing, as the Mac's Go menu does.
 *
 * Resolved here rather than labelled in the menu because the order is the
 * user's: they drag rows around, and a label baked in when the menu was built
 * would be wrong the first time they did.
 */
function openSidebarRow(rank: number, handlers: MenuHandlers): void {
  const sections = sidebarSections(handlers.features, {
    query: "",
    sidebarOrder: handlers.workspace.layout.sidebarOrder,
    categoryOrder: handlers.workspace.layout.categoryOrder,
    collapsedCategories: handlers.workspace.layout.collapsedCategories,
    favorites: handlers.workspace.layout.favorites,
    disabledFeatures: handlers.workspace.layout.disabledFeatures,
  })
  const feature = visibleFeatures(sections)[rank]
  if (feature) handlers.workspace.open(feature.id)
}

function activeOf(workspace: WorkspaceController): string | null {
  const group = workspace.workspace.groups[workspace.workspace.focusedGroup]
  return group?.activeTab ?? null
}

function ignore() {}
