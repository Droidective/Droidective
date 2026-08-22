import { SmartphoneNfc } from "lucide-react"
import { connectDeviceHint } from "@/lib/hints"

/**
 * The Mac's `NoDeviceView` — a `ContentUnavailableView` with the `iphone.slash`
 * symbol, the heading "No device connected", and a line saying what *this*
 * screen needs one for.
 *
 * Every ported screen used to print a bare grey sentence in the top-left
 * instead, which is neither the same layout nor the same weight; on the Mac
 * this is a centred, titled empty state and it is what someone sees before
 * they have plugged anything in.
 */
export function NoDevice({ feature, title }: { feature: string; title: string }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
      <SmartphoneNfc size={26} className="text-text-tertiary" />
      <h2 className="text-[15px] font-medium text-text-primary">No device connected</h2>
      <p className="max-w-sm text-text-secondary">{connectDeviceHint(feature, title)}</p>
    </div>
  )
}
