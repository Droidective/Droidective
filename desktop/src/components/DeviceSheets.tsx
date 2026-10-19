import { ConfirmDialog } from "@/components/ConfirmDialog"
import { PhoneSetupSheet } from "@/components/PhoneSetupSheet"
import { WirelessSheet, type WirelessMode } from "@/components/WirelessSheet"
import { prepareTitle } from "@/lib/tailnet"
import type { Device, PhoneSetupOffer } from "@/lib/wire"

/** The sheet the device bar has up — at most one, as on the Mac. */
export type DeviceSheet =
  | { kind: "wireless"; mode: WirelessMode }
  | { kind: "phone-setup"; device: Device }
  /** "Prepare … for Tailscale…", with the warning the daemon served. */
  | { kind: "tailscale-prepare"; device: Device; warning: string }

/**
 * The sheets the device dropdown opens: the wireless pair & connect sheet,
 * set-up for Droidective for Android, and the question "Prepare for Tailscale"
 * asks. Hosted by the bar rather than the menu, because the menu closes as the
 * sheet opens.
 */
export function DeviceSheets({
  sheet,
  devices,
  onSelectDevice,
  onPhoneOffer,
  onPrepareForTailscale,
  onDismiss,
}: {
  sheet: DeviceSheet | null
  devices: Device[]
  onSelectDevice: (serial: string) => void
  /** What the set-up sheet's last read says to offer, so the menu entry changes at once. */
  onPhoneOffer: (serial: string, offer: PhoneSetupOffer | null) => void
  /** `adb tcpip 5555`, once the warning has been confirmed. */
  onPrepareForTailscale: (device: Device) => void
  onDismiss: () => void
}) {
  if (sheet === null) return null
  switch (sheet.kind) {
    case "wireless":
      return (
        <WirelessSheet
          mode={sheet.mode}
          devices={devices}
          onSelectDevice={onSelectDevice}
          onDismiss={onDismiss}
        />
      )
    case "phone-setup": {
      const { serial, label } = sheet.device
      return (
        <PhoneSetupSheet
          serial={serial}
          name={label}
          onOffer={(offer) => {
            onPhoneOffer(serial, offer)
          }}
          onDismiss={onDismiss}
        />
      )
    }
    case "tailscale-prepare":
      // Not destructive-styled: it is a warning to read, and the Mac's
      // confirm button is a plain Prepare.
      return (
        <ConfirmDialog
          title={prepareTitle(sheet.device.label)}
          message={sheet.warning}
          confirmLabel="Prepare"
          destructive={false}
          onConfirm={() => {
            onDismiss()
            onPrepareForTailscale(sheet.device)
          }}
          onCancel={onDismiss}
        />
      )
  }
}
