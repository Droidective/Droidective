import { HubColumn } from "@/components/Hub"
import { PrivateDnsSection } from "@/components/PrivateDnsSection"
import { NoDevice } from "@/components/screen"
import type { Device } from "@/lib/wire"

/**
 * The standalone Private DNS screen — the Mac's `PrivateDnsView`, which is
 * `HubColumn { PrivateDnsSection() }`.
 *
 * The Connection hub shows the same section, so everything it does lives there.
 */
export function PrivateDnsPane({ device }: { device: Device | null }) {
  if (!device) return <NoDevice feature="private-dns" title="Private DNS" />

  return (
    <HubColumn>
      <PrivateDnsSection serial={device.serial} />
    </HubColumn>
  )
}
