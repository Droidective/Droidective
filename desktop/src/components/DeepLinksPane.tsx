import { DeepLinksSection } from "@/components/DeepLinksSection"
import { HubColumn } from "@/components/Hub"
import { NoDevice } from "@/components/screen"
import type { Device } from "@/lib/wire"

/**
 * The standalone Deep Links screen — the Mac's `DeepLinksView`, which is
 * `HubColumn { DeepLinksSection() }` and nothing else.
 *
 * Everything it shows lives in the section, because the React Native hub shows
 * the same one. Only the device gate is the screen's own: the hub has sections
 * that work without a device and this does not.
 */
export function DeepLinksPane({
  device,
  packageId,
}: {
  device: Device | null
  packageId: string | null
}) {
  if (!device) return <NoDevice feature="deep-link" title="Deep Links" />

  return (
    <HubColumn>
      <DeepLinksSection packageId={packageId} />
    </HubColumn>
  )
}
