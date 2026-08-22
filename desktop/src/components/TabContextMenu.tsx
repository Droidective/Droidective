import { TabMenu, type TabMenuTarget } from "@/components/TabMenu"

// Re-exported because it is this component's own prop type: a caller that
// renders the menu needs the target, and making it reach into a second module
// for it is two imports for one idea.
export type { TabMenuTarget }
import type { WorkspaceController } from "@/hooks/useWorkspace"
import { isSplit } from "@/lib/workspace"

/**
 * The tab menu, wired to the workspace.
 *
 * Its own component so `App` does not carry six closures that all do the same
 * thing — act on a tab, then close the menu.
 */
export function TabContextMenu({
  target,
  workspace,
  onDismiss,
}: {
  target: TabMenuTarget
  workspace: WorkspaceController
  onDismiss: () => void
}) {
  const act = (run: (id: string) => void) => () => {
    run(target.id)
    onDismiss()
  }
  const pane = workspace.workspace.groups.find((group) => group.openTabs.includes(target.id))
  return (
    <TabMenu
      target={target}
      isSplit={isSplit(workspace.workspace)}
      canCloseOthers={(pane?.openTabs.length ?? 0) > 1}
      onSplit={act(workspace.split)}
      onMoveToOtherPane={act(workspace.moveToOtherPane)}
      onClose={act(workspace.close)}
      onCloseOthers={act(workspace.closeOthers)}
      onDismiss={onDismiss}
    />
  )
}
