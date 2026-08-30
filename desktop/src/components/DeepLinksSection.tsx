import { useState } from "react"
import { Plus } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { DeepLinkEditor } from "@/components/DeepLinkEditor"
import { DeepLinkRow } from "@/components/DeepLinkRow"
import { HubSection } from "@/components/Hub"
import { ConfirmDialog } from "@/components/screen"
import { useDeepLinks } from "@/hooks/useDeepLinks"
import type { DeepLink } from "@/lib/wire"

/**
 * Saved deep links for the chosen app — the Mac's `DeepLinksSection`.
 *
 * A section rather than a screen, because the Mac's is: `DeepLinksView` is
 * `HubColumn { DeepLinksSection() }` and the React Native hub embeds the very
 * same view. Two copies would drift, and the one that drifted would be the one
 * nobody opened.
 *
 * Saved **per app**. With none chosen this says so inline rather than replacing
 * the screen, which is what lets it sit in a hub between sections that do not
 * need an app at all.
 *
 * The list lives in the daemon's store, the same file the Mac app writes; the
 * Mac keys it by saved-bundle id and this keys it by package id, so the two sets
 * sit side by side rather than merging. A launch goes to every targeted device
 * and reports per device.
 */
export function DeepLinksSection({ packageId }: { packageId: string | null }) {
  const links = useDeepLinks(packageId)
  const [editing, setEditing] = useState<DeepLink | "new" | null>(null)
  const [pendingDelete, setPendingDelete] = useState<DeepLink | null>(null)

  return (
    <>
      <HubSection
        title="Deep links"
        subtitle="Saved per app — launch a URL on the device in one click."
      >
        {links.error === null ? null : <Banner tone="error">{links.error.message}</Banner>}

        {packageId === null ? (
          <p className="text-text-tertiary">
            Pick an app in Apps — deep links are saved per app.
          </p>
        ) : (
          <>
            {links.links.length === 0 ? (
              <p className="text-text-secondary">
                No deep links yet. Add one like myapp://orders/123 to launch it in a click.
              </p>
            ) : (
              <div className="overflow-hidden rounded-lg bg-bg-root">
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
          </>
        )}
      </HubSection>

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
    </>
  )
}
