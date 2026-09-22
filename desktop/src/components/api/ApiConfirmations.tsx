import { AlertDialog } from "@/components/AlertDialog"
import { ConfirmDialog } from "@/components/ConfirmDialog"
import type { PendingDelete } from "@/components/api/ApiSheetHost"

/**
 * The pane's modals: two questions and one statement.
 *
 * A dialog rather than an armed button, as everywhere else in this app:
 * arming is a different interaction someone moving between the two platforms
 * would have to relearn. The statement is an import or an export that could not
 * be done — the Mac alerts on those three rather than filing them as a toast,
 * because they are the answer to what was just asked for.
 */
export function ApiConfirmations({
  pendingDelete,
  onResolveDelete,
  pendingNew,
  currentName,
  onSaveFirst,
  onDiscard,
  onKeepEditing,
  alert,
  onDismissAlert,
}: {
  pendingDelete: PendingDelete | null
  onResolveDelete: () => void
  pendingNew: boolean
  currentName: string
  onSaveFirst: () => void
  onDiscard: () => void
  onKeepEditing: () => void
  alert: string | null
  onDismissAlert: () => void
}) {
  return (
    <>
      {pendingDelete === null ? null : (
        <ConfirmDialog
          title={pendingDelete.title}
          message={pendingDelete.message}
          confirmLabel={pendingDelete.confirmLabel}
          onConfirm={() => {
            pendingDelete.run()
            onResolveDelete()
          }}
          onCancel={onResolveDelete}
        />
      )}
      {pendingNew ? (
        <ConfirmDialog
          title="Discard unsaved changes?"
          message={`“${currentName}” has edits that aren't saved to a collection.`}
          confirmLabel="Discard and Start New"
          extraLabel="Save First…"
          onExtra={onSaveFirst}
          onConfirm={onDiscard}
          onCancel={onKeepEditing}
        />
      ) : null}
      {alert === null ? null : (
        <AlertDialog title="API Testing" message={alert} onDismiss={onDismissAlert} />
      )}
    </>
  )
}
