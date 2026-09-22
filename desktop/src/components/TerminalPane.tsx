import { useEffect, useRef, useState } from "react"
import { SplitLayout } from "@/components/TerminalSplitLayout"
import { TabStrip } from "@/components/TerminalTabStrip"
import { useRegisterTerminalCommands } from "@/hooks/useTerminalCommands"
import { useTerminalTabs } from "@/hooks/useTerminalTabs"
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
