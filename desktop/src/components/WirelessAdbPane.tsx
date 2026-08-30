import { HubColumn } from "@/components/Hub"
import { WirelessAdbSection } from "@/components/WirelessAdbSection"

/**
 * The standalone Wireless ADB screen — the Mac's `WirelessAdbView`, which is
 * `HubColumn { WirelessAdbSection() }`.
 *
 * The Connection hub shows the same sections, so everything they do lives
 * there.
 */
export function WirelessAdbPane() {
  return (
    <HubColumn>
      <WirelessAdbSection />
    </HubColumn>
  )
}
