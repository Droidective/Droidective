import { Plus } from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { SplitLayout } from "@/components/TerminalSplitLayout"
import { TabChip, type Strip } from "@/components/TerminalTabChip"
import { groupOfTab } from "@/lib/terminal-groups"
import { TerminalTabMenu } from "@/components/TerminalTabMenu"
import { useRegisterTerminalCommands } from "@/hooks/useTerminalCommands"
import { useTerminalTabs, type TerminalTabs } from "@/hooks/useTerminalTabs"
import { IS_MAC } from "@/lib/platform"
import { cn } from "@/lib/cn"

/**
 * The Terminal — login shells on the host, over the daemon's `pty` topic.
 *
 * A Chrome-style top strip, which is what the Mac's terminal defaults to since
 * v3.1.0. Tabs split into panes and stay alive while hidden: a shell is someone's
 * working state, and a tab switch that killed it would make the feature useless
 * for the thing it is for.
 *
 * `serial` scopes a *new* shell to the selected device by exporting
 * `ANDROID_SERIAL`, so adb inside it needs no `-s`. Captured per pane at open,
 * never re-applied — see `TerminalShellProps.serial`.
 */
export function TerminalPane({ serial }: { serial: string | null }) {
  const tabs = useTerminalTabs()
  const { openTab } = tabs
  // Opened *once*, tracked in a ref rather than by "are there no tabs?".
  //
  // Two reasons, and the first one bit: React runs an effect twice in
  // development, and both passes see the same empty tab list — so the feature
  // opened with two shells, which is two ptys and two prompts for one click.
  // The second is the behaviour after that: closing the last tab leaves the
  // pane empty with a + to open another, rather than immediately conjuring a
  // shell nobody asked for.
  const opened = useRef(false)
  useEffect(() => {
    if (opened.current) return
    opened.current = true
    openTab(serial)
  }, [openTab, serial])

  const active = tabs.tabs.find((tab) => tab.id === tabs.active) ?? null
  // Which tab's name is being edited, so the menu's Rename can start it too.
  const [renaming, setRenaming] = useState<string | null>(null)

  // What the window menu drives. Registered while this pane is mounted, which
  // is also what greys the menu's terminal commands in and out.
  useRegisterTerminalCommands({
    newTab: () => {
      tabs.openTab(serial)
    },
    split: (direction) => {
      tabs.split(direction, serial)
    },
    closeFocused: () => {
      if (active !== null) tabs.closePane(active.id, active.focused)
    },
    renameFocused: () => {
      setRenaming(active?.id ?? null)
    },
    cycle: tabs.cycle,
  })

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <TabStrip
        tabs={tabs}
        serial={serial}
        renaming={renaming}
        onRename={setRenaming}
      />
      {/*
        Every tab stays mounted; the inactive ones are hidden rather than
        unmounted, because unmounting is what would hang up the shell.
      */}
      {tabs.tabs.map((tab) => (
        <div
          key={tab.id}
          className={cn("min-h-0 flex-1", tab.id === tabs.active ? "flex" : "hidden")}
        >
          <SplitLayout node={tab.tree} tab={tab} tabs={tabs} />
        </div>
      ))}
      {active === null ? (
        <div className="flex flex-1 items-center justify-center text-text-tertiary">
          No shells open.
        </div>
      ) : null}
    </div>
  )
}

function TabStrip({
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
  const strip: Strip = { tabs, renaming, onRename, onMenu: setMenu }
  return (
    <div className="flex shrink-0 items-center gap-1 border-b border-border-subtle bg-bg-chrome px-2 py-1">
      {tabs.entries.map((entry) =>
        entry.kind === "tab" ? (
          <TabChip key={entry.id} id={entry.id} strip={strip} />
        ) : (
          // A group is its name and the tabs inside it, boxed. The Mac's rail
          // is vertical and collapses a group to its header; this strip is
          // horizontal, and what someone needs to see here is which tabs
          // belong together.
          <span
            key={entry.group.id}
            className="flex items-center gap-1 rounded border border-border-subtle px-1"
          >
            <span className="px-1 text-text-tertiary">{entry.group.name}</span>
            {entry.group.tabIds.map((id) => (
              <TabChip key={id} id={id} strip={strip} />
            ))}
          </span>
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
