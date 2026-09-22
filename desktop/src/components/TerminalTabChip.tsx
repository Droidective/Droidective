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
import type { Drag } from "@/lib/terminal-drop"
import type { TabGroup } from "@/lib/terminal-groups"

/** What every tab chip in the strip needs, whether loose or in a group. */
export interface Strip {
  tabs: TerminalTabs
  renaming: string | null
  onRename: (tab: string | null) => void
  onMenu: (menu: { id: string; x: number; y: number }) => void
  /**
   * The drag in flight, if any.
   *
   * Held by the strip rather than read off the `dataTransfer`, because
   * `dragover` cannot read it — the browser only exposes the payload on drop,
   * and the insertion cue has to be drawn before then.
   */
  dragging: Drag | null
  onDrag: (drag: Drag | null) => void
}

/** One tab in the strip: its name, its rename field, and its close. */
export function TabChip({ id, strip }: { id: string; strip: Strip }) {
  const { tabs, renaming, onRename, onMenu } = strip
  const tab = tabs.tabs.find((one) => one.id === id)
  // A group can name a tab the strip has since closed; drawing nothing is
  // right, and the model drops it on the next change.
  if (tab === undefined) return null
  const { dragging, onDrag } = strip
  return (
    <div
      draggable
      onDragStart={(event) => {
        event.dataTransfer.effectAllowed = "move"
        // Something has to be set or Firefox refuses the drag; the payload
        // itself is `dragging`, which `dragover` can actually read.
        event.dataTransfer.setData("text/plain", tab.id)
        onDrag({ kind: "tab", id: tab.id })
      }}
      onDragEnd={() => onDrag(null)}
      onDragOver={(event) => {
        if (dragging !== null) event.preventDefault()
      }}
      onDrop={(event) => {
        if (dragging === null) return
        event.preventDefault()
        event.stopPropagation()
        tabs.dropOn(dragging, { kind: "tab", id: tab.id })
        onDrag(null)
      }}
      className={cn(
        "group flex cursor-grab items-center gap-1 rounded px-2 py-1",
        tab.id === tabs.active
          ? "bg-bg-raised text-text-primary"
          : "text-text-secondary hover:bg-bg-surface",
        dragging?.kind === "tab" && dragging.id === tab.id ? "opacity-40" : "",
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

/**
 * A group: its name and the tabs inside it, boxed.
 *
 * The Mac's rail is vertical and collapses a group to its header; this strip is
 * horizontal, and what someone needs to see here is which tabs belong together.
 *
 * The *name* is the group's own drag handle, matching the Mac, where a group
 * moves by its header rather than by any tab in it. Dropping a tab anywhere on
 * the box joins the group — that is the Mac's header drop, and the box is what
 * a header is here.
 */
export function GroupBox({ group, strip }: { group: TabGroup; strip: Strip }) {
  const { tabs, dragging, onDrag } = strip
  return (
    <span
      onDragOver={(event) => {
        if (dragging !== null) event.preventDefault()
      }}
      onDrop={(event) => {
        if (dragging === null) return
        event.preventDefault()
        event.stopPropagation()
        tabs.dropOn(dragging, { kind: "group", id: group.id })
        onDrag(null)
      }}
      className={cn(
        "flex items-center gap-1 rounded border border-border-subtle px-1",
        dragging?.kind === "group" && dragging.id === group.id ? "opacity-40" : "",
      )}
    >
      <span
        draggable
        onDragStart={(event) => {
          event.dataTransfer.effectAllowed = "move"
          event.dataTransfer.setData("text/plain", group.id)
          onDrag({ kind: "group", id: group.id })
        }}
        onDragEnd={() => onDrag(null)}
        className="cursor-grab px-1 text-text-tertiary"
        title={`${group.name} — drag to reorder`}
      >
        {group.name}
      </span>
      {group.tabIds.map((id) => (
        <TabChip key={id} id={id} strip={strip} />
      ))}
    </span>
  )
}
