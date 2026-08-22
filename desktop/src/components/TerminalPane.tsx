import { Plus, X } from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { TerminalShell } from "@/components/TerminalShell"
import { useRegisterTerminalCommands } from "@/hooks/useTerminalCommands"
import { tabLabel, useTerminalTabs, type TerminalTab, type TerminalTabs } from "@/hooks/useTerminalTabs"
import { IS_MAC } from "@/lib/platform"
import { firstPaneId, type SplitNode } from "@/lib/terminal"
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
  return (
    <div className="flex shrink-0 items-center gap-1 border-b border-border-subtle bg-bg-chrome px-2 py-1">
      {tabs.tabs.map((tab) => (
        <div
          key={tab.id}
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
              title={tabs.serials[tab.focused] ?? "No device scoped"}
            >
              {tabLabel(tab)}
            </button>
          )}
          <button
            type="button"
            aria-label={`Close shell ${String(tab.ordinal)}`}
            className="text-text-tertiary opacity-0 group-hover:opacity-100 hover:text-text-primary"
            onClick={() => tabs.closeTab(tab.id)}
          >
            <X size={12} />
          </button>
        </div>
      ))}
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
function SplitLayout({
  node,
  tab,
  tabs,
}: {
  node: SplitNode
  tab: TerminalTab
  tabs: TerminalTabs
}) {
  if (node.kind === "pane") {
    const focused = tab.focused === node.id && tab.id === tabs.active
    return (
      <div
        className={cn(
          "flex min-h-0 min-w-0 flex-1 border",
          focused ? "border-accent/40" : "border-transparent",
        )}
        onFocusCapture={() => tabs.focus(tab.id, node.id)}
      >
        <TerminalShell
          serial={tabs.serials[node.id] ?? null}
          active={focused}
          onExit={() => tabs.closePane(tab.id, node.id)}
        />
      </div>
    )
  }
  return (
    <div
      className={cn(
        "flex min-h-0 min-w-0 flex-1 gap-px",
        node.direction === "vertical" ? "flex-row" : "flex-col",
      )}
    >
      {node.children.map((child) => (
        <SplitLayout key={firstPaneId(child) ?? ""} node={child} tab={tab} tabs={tabs} />
      ))}
    </div>
  )
}
