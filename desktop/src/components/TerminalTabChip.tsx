/**
 * One tab in the terminal's strip.
 *
 * Its own file because `TerminalPane` is at oxlint's line ceiling, and because
 * a chip is drawn from two places now: loose, and inside a group.
 */

import { X } from "lucide-react"
import { useState } from "react"

import { tabLabel, type TerminalTabs } from "@/hooks/useTerminalTabs"
import { cn } from "@/lib/cn"

/** What every tab chip in the strip needs, whether loose or in a group. */
export interface Strip {
  tabs: TerminalTabs
  renaming: string | null
  onRename: (tab: string | null) => void
  onMenu: (menu: { id: string; x: number; y: number }) => void
}

/** One tab in the strip: its name, its rename field, and its close. */
export function TabChip({ id, strip }: { id: string; strip: Strip }) {
  const { tabs, renaming, onRename, onMenu } = strip
  const tab = tabs.tabs.find((one) => one.id === id)
  // A group can name a tab the strip has since closed; drawing nothing is
  // right, and the model drops it on the next change.
  if (tab === undefined) return null
  return (
    <div
      className={cn(
        "group flex items-center gap-1 rounded px-2 py-1",
        tab.id === tabs.active
          ? "bg-bg-raised text-text-primary"
          : "text-text-secondary hover:bg-bg-surface",
      )}
    >
      {renaming === tab.id ? (
        <TabNameField
          value={tabLabel(tab)}
          onCommit={(name) => {
            tabs.rename(tab.id, name)
            onRename(null)
          }}
        />
      ) : (
        <button
          type="button"
          onClick={() => tabs.select(tab.id)}
          onDoubleClick={() => onRename(tab.id)}
          onContextMenu={(event) => {
            event.preventDefault()
            tabs.select(tab.id)
            onMenu({ id: tab.id, x: event.clientX, y: event.clientY })
          }}
          title={tabs.serials[tab.focused] ?? "No device scoped"}
        >
          {tabLabel(tab)}
        </button>
      )}
      <button
        type="button"
        // The Mac's wording: what makes this different from closing a tab
        // anywhere else in the app is that a live shell dies with it.
        title="Close this terminal (kills its shell)"
        aria-label={`Close shell ${String(tab.ordinal)}`}
        className="text-text-tertiary opacity-0 group-hover:opacity-100 hover:text-text-primary"
        onClick={() => tabs.closeTab(tab.id)}
      >
        <X size={12} />
      </button>
    </div>
  )
}

/**
 * The rename field. Commits on Return or on losing focus, cancels on Escape —
 * the shape of the Mac's rename sheet, minus the sheet: a tab is one word, and a
 * dialog for one word is a dialog too many.
 */
function TabNameField({
  value,
  onCommit,
}: {
  value: string
  onCommit: (name: string) => void
}) {
  const [draft, setDraft] = useState(value)
  return (
    <input
      // eslint-disable-next-line jsx-a11y/no-autofocus
      autoFocus
      className="w-24 rounded bg-bg-root px-1 text-text-primary outline-none"
      value={draft}
      onChange={(event) => setDraft(event.target.value)}
      onBlur={() => onCommit(draft)}
      onKeyDown={(event) => {
        // Stopped here so the pane's own capture handler does not read a
        // shortcut out of someone typing a tab name.
        event.stopPropagation()
        if (event.key === "Enter") onCommit(draft)
        if (event.key === "Escape") onCommit(value)
      }}
    />
  )
}

/**
 * One tab's panes.
 *
 * Keyed by the subtree's first pane rather than its index: the panes after a
 * closed one shift slots, and React would hand an existing DOM node — with a
 * live shell drawing into it — to a different pane.
 */
/** The tab strip's right-click menu, and what each item does. */
