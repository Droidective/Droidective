/**
 * The terminal's horizontal tab strip: chips, group boxes, and the drag.
 *
 * Its own file because `TerminalPane` is at oxlint's dependency ceiling, and
 * because the strip is where every drag target lives — the chips, the group
 * boxes, and the strip itself as the "past the last one" target.
 */

import { Plus } from "lucide-react"
import { useState } from "react"

import { GroupBox, TabChip, type Strip } from "@/components/TerminalTabChip"
import { TerminalTabMenu } from "@/components/TerminalTabMenu"
import type { TerminalTabs } from "@/hooks/useTerminalTabs"
import { IS_MAC } from "@/lib/platform"
import type { Drag } from "@/lib/terminal-drop"
import { groupOfTab } from "@/lib/terminal-groups"


export function TabStrip({
  tabs,
  serial,
  renaming,
  onRename,
}: {
  tabs: TerminalTabs
  serial: string | null
  renaming: string | null
  onRename: (tab: string | null) => void
}) {
  const modifier = IS_MAC ? "⇧⌘" : "Ctrl+Shift+"
  const [menu, setMenu] = useState<{ id: string; x: number; y: number } | null>(null)
  const [dragging, setDragging] = useState<Drag | null>(null)
  const strip: Strip = { tabs, renaming, onRename, onMenu: setMenu, dragging, onDrag: setDragging }
  return (
    <div
      className="flex shrink-0 items-center gap-1 border-b border-border-subtle bg-bg-chrome px-2 py-1"
      onDragOver={(event) => {
        if (dragging !== null) event.preventDefault()
      }}
      onDrop={(event) => {
        // The strip itself is the "past the last one" target. A chip or a
        // group that took the drop stopped it before it reached here.
        if (dragging === null) return
        event.preventDefault()
        tabs.dropOn(dragging, { kind: "end" })
        setDragging(null)
      }}
    >
      {tabs.entries.map((entry) =>
        entry.kind === "tab" ? (
          <TabChip key={entry.id} id={entry.id} strip={strip} />
        ) : (
          <GroupBox key={entry.group.id} group={entry.group} strip={strip} />
        ),
      )}
      <TabMenu menu={menu} setMenu={setMenu} tabs={tabs} serial={serial} onRename={onRename} />
      <button
        type="button"
        aria-label="New shell"
        title={`New shell (${modifier}T)`}
        className="rounded p-1 text-text-secondary hover:bg-bg-surface hover:text-text-primary"
        onClick={() => tabs.openTab(serial)}
      >
        <Plus size={14} />
      </button>
      {/* The same accelerators the File menu shows. A hint here because the
          menu is where they are declared but not where anyone looks first. */}
      <span className="ml-auto text-text-tertiary">
        {modifier}N new · {modifier}D beside · {modifier}E below · {modifier}W close
      </span>
    </div>
  )
}

function TabMenu({
  menu,
  setMenu,
  tabs,
  serial,
  onRename,
}: {
  menu: { id: string; x: number; y: number } | null
  setMenu: (menu: null) => void
  tabs: TerminalTabs
  serial: string | null
  onRename: (tab: string) => void
}) {
  if (menu === null) return null
  // Which group this tab is in, if any: the two group verbs would otherwise
  // act on nothing.
  const group = groupOfTab(tabs.entries, menu.id)
  const pick = (run: () => void) => () => {
    setMenu(null)
    run()
  }
  return (
    <TerminalTabMenu
      at={menu}
      onRename={pick(() => {
        onRename(menu.id)
      })}
      onSplitVertically={pick(() => {
        tabs.split("vertical", serial)
      })}
      onSplitHorizontally={pick(() => {
        tabs.split("horizontal", serial)
      })}
      onClose={pick(() => {
        tabs.closeTab(menu.id)
      })}
      onNewGroup={pick(() => {
        // Created with the default name and renamed from the header, rather
        // than a prompt standing in the way of the gesture.
        tabs.newGroup(menu.id, "")
      })}
      onNewTerminalHere={
        group === null
          ? null
          : pick(() => {
              tabs.openInGroup(group.id, serial)
            })
      }
      onCloseGroup={
        group === null
          ? null
          : pick(() => {
              tabs.closeGroup(group.id)
            })
      }
      onDismiss={() => {
        setMenu(null)
      }}
    />
  )
}
