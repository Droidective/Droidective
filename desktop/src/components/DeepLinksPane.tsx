import { useState } from "react"
import { Plus } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { DeepLinkEditor } from "@/components/DeepLinkEditor"
import { DeepLinkRow } from "@/components/DeepLinkRow"
import { ConfirmDialog, NoDevice } from "@/components/screen"
import { NoBundle } from "@/components/NoBundle"
import { useDeepLinks } from "@/hooks/useDeepLinks"
import type { DeepLink, Device } from "@/lib/wire"

/**
 * Saved deep links for the chosen app — the Mac's `DeepLinksSection`.
 *
 * Saved **per app**, which is why this needs one picked in Apps before it shows
 * anything. The list lives in the daemon's store, the same file the Mac app
 * writes; the Mac keys it by saved-bundle id and this keys it by package id, so
 * the two sets sit side by side rather than merging. A launch goes to every
 * targeted device and reports per device.
 */
export function DeepLinksPane({
  device,
  packageId,
}: {
  device: Device | null
  packageId: string | null
}) {
  const links = useDeepLinks(packageId)
  const [editing, setEditing] = useState<DeepLink | "new" | null>(null)
  const [pendingDelete, setPendingDelete] = useState<DeepLink | null>(null)

  if (!device) return <NoDevice feature="deep-link" title="Deep Links" />
  if (packageId === null) return <NoBundle what="save deep links for it" />

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <div className="mx-auto flex w-full max-w-[620px] flex-col gap-3 p-4">
        {links.error === null ? null : <Banner tone="error">{links.error.message}</Banner>}

        <header>
          <h2 className="text-[15px] font-medium text-text-primary">Deep links</h2>
          <p className="text-text-tertiary">
            Saved per app — launch a URL on the device in one click. {packageId}
          </p>
        </header>

        {links.links.length === 0 ? (
          <p className="rounded-lg bg-bg-surface p-4 text-text-secondary">
            No deep links yet. Add one like myapp://orders/123 to launch it in a click.
          </p>
        ) : (
          <div className="overflow-hidden rounded-lg bg-bg-surface">
            {links.links.map((link, index) => (
              <DeepLinkRow
                key={link.id}
                link={link}
                first={index === 0}
                canLaunch={links.canLaunch}
                onLaunch={() => {
                  links.launch(link)
                }}
                onEdit={() => {
                  setEditing(link)
                }}
                onDelete={() => {
                  setPendingDelete(link)
                }}
              />
            ))}
          </div>
        )}

        <div>
          <Button
            onClick={() => {
              setEditing("new")
            }}
          >
            <span className="flex items-center gap-1.5">
              <Plus size={12} />
              Add deep link
            </span>
          </Button>
        </div>
      </div>

      {editing === null ? null : (
        <DeepLinkEditor
          link={editing === "new" ? null : editing}
          onCancel={() => {
            setEditing(null)
          }}
          onSave={(link) => {
            setEditing(null)
            links.save(link)
          }}
        />
      )}

      {pendingDelete === null ? null : (
        <ConfirmDialog
          title={`Delete “${pendingDelete.label === "" ? pendingDelete.url : pendingDelete.label}”?`}
          message="This can't be undone."
          confirmLabel="Delete"
          onConfirm={() => {
            const target = pendingDelete
            setPendingDelete(null)
            links.remove(target)
          }}
          onCancel={() => {
            setPendingDelete(null)
          }}
        />
      )}
    </div>
  )
}
