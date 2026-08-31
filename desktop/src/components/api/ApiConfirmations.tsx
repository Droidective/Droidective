import { ConfirmDialog } from "@/components/ConfirmDialog"
import type { PendingDelete } from "@/components/api/ApiSheetHost"

/**
 * The two questions the pane asks.
 *
 * A dialog rather than an armed button, as everywhere else in this app:
 * arming is a different interaction someone moving between the two platforms
 * would have to relearn.
 */
export function ApiConfirmations({
  pendingDelete,
  onResolveDelete,
  pendingNew,
  currentName,
  onSaveFirst,
  onDiscard,
  onKeepEditing,
}: {
  pendingDelete: PendingDelete | null
  onResolveDelete: () => void
  pendingNew: boolean
  currentName: string
  onSaveFirst: () => void
  onDiscard: () => void
  onKeepEditing: () => void
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
    </>
  )
}
