import { Package } from "lucide-react"

/**
 * The "no bundle selected" empty state — the Mac's `shippingbox`
 * `ContentUnavailableView`.
 *
 * A distinct state from having no device: the four per-app screens need both,
 * and telling someone to connect a device when one is already plugged in is
 * the kind of wrong instruction that costs a minute every time.
 */
export function NoBundle({ what }: { what: string }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
      <Package size={26} className="text-text-tertiary" />
      <h2 className="text-[15px] font-medium text-text-primary">No app selected</h2>
      <p className="max-w-sm text-text-secondary">Pick an app in Apps to {what}.</p>
    </div>
  )
}

/** The Mac's "Not installed" state, for a bundle this device does not have. */
export function NotInstalled({ packageId }: { packageId: string }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
      <Package size={26} className="text-text-tertiary" />
      <h2 className="text-[15px] font-medium text-text-primary">Not installed</h2>
      <p className="max-w-sm text-text-secondary">
        {packageId} isn&rsquo;t installed on this device.
      </p>
    </div>
  )
}
