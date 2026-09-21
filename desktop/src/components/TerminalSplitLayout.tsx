/**
 * One tab's split tree, drawn.
 *
 * Its own file because `TerminalPane` is at oxlint's line ceiling, and the
 * pane is the part that keeps growing.
 */

import { X } from "lucide-react"

import { TerminalShell } from "@/components/TerminalShell"
import type { TerminalTab, TerminalTabs } from "@/hooks/useTerminalTabs"
import { cn } from "@/lib/cn"
import { firstPaneId, type SplitNode } from "@/lib/terminal"

export function SplitLayout({
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
    // Only in a split: the tab strip's own × closes the last pane, and two
    // close buttons on one shell is a way to lose a session by accident.
    const split = tab.tree.kind === "split"
    return (
      <div
        className={cn(
          "group/pane relative flex min-h-0 min-w-0 flex-1 border",
          focused ? "border-accent/40" : "border-transparent",
        )}
        onFocusCapture={() => tabs.focus(tab.id, node.id)}
      >
        <TerminalShell
          serial={tabs.serials[node.id] ?? null}
          active={focused}
          onExit={() => tabs.closePane(tab.id, node.id)}
        />
        {split ? (
          <button
            type="button"
            // The Mac's wording, and it earns its length: what makes this
            // different from closing a pane anywhere else is that a live shell
            // dies with it.
            title="Close this pane (kills its shell)"
            aria-label="Close this pane"
            onClick={() => tabs.closePane(tab.id, node.id)}
            className="absolute right-1 top-1 rounded p-0.5 text-text-tertiary opacity-0 group-hover/pane:opacity-100 hover:text-text-primary"
          >
            <X size={11} />
          </button>
        ) : null}
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
