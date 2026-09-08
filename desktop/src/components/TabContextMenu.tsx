import { TabMenu, type TabMenuTarget } from "@/components/TabMenu"

// Re-exported because it is this component's own prop type: a caller that
// renders the menu needs the target, and making it reach into a second module
// for it is two imports for one idea.
export type { TabMenuTarget }
import type { WorkspaceController } from "@/hooks/useWorkspace"
import { HOME_TAB } from "@/lib/layout"
import { closable, isPinned, isSplit } from "@/lib/workspace"

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
  return (
    <TabMenu
      target={target}
      isSplit={isSplit(workspace.workspace)}
      // Pinned tabs and Home are spared, so count what would actually close
      // rather than the chips on screen — otherwise the row is enabled beside
      // a strip of pinned tabs and does nothing.
      canCloseOthers={closable(workspace.workspace, target.id, HOME_TAB).length > 0}
      isPinned={isPinned(workspace.workspace, target.id)}
      onTogglePin={act(workspace.toggleTabPin)}
      onSplit={act(workspace.split)}
      onMoveToOtherPane={act(workspace.moveToOtherPane)}
      onClose={act(workspace.close)}
      onCloseOthers={act(workspace.closeOthers)}
      onDismiss={onDismiss}
    />
  )
}
