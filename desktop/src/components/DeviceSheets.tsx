import { PhoneSetupSheet } from "@/components/PhoneSetupSheet"
import { WirelessSheet, type WirelessMode } from "@/components/WirelessSheet"
import type { Device, PhoneSetupStatus } from "@/lib/wire"

/** The sheet the device bar has up — at most one, as on the Mac. */
export type DeviceSheet =
  | { kind: "wireless"; mode: WirelessMode }
  | { kind: "phone-setup"; device: Device }

/**
 * The sheets the device dropdown opens: the wireless pair & connect sheet, and
 * set-up for Droidective for Android. Hosted by the bar rather than the menu,
 * because the menu closes as the sheet opens.
 */
export function DeviceSheets({
  sheet,
  devices,
  onSelectDevice,
  onPhoneStatus,
  onDismiss,
}: {
  sheet: DeviceSheet | null
  devices: Device[]
  onSelectDevice: (serial: string) => void
  /** What the set-up sheet read, so the menu entry goes once set-up is done. */
  onPhoneStatus: (serial: string, status: PhoneSetupStatus) => void
  onDismiss: () => void
}) {
  if (sheet === null) return null
  if (sheet.kind === "wireless") {
    return (
      <WirelessSheet
        mode={sheet.mode}
        devices={devices}
        onSelectDevice={onSelectDevice}
        onDismiss={onDismiss}
      />
    )
  }
  const { serial, label } = sheet.device
  return (
    <PhoneSetupSheet
      serial={serial}
      name={label}
      onStatus={(status) => {
        onPhoneStatus(serial, status)
      }}
      onDismiss={onDismiss}
    />
  )
}
