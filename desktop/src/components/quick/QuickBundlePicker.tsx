import { QuickList } from "@/components/quick/QuickParts"
import { useQuickBundle } from "@/hooks/useQuickBundle"

/**
 * Which app the held action runs against — the panel's pick-an-app step.
 *
 * It appears only after the device is settled, because "which app" is a
 * question about a particular device: asking first and then which device would
 * be asking about a list that might not exist there.
 */
export function QuickBundlePicker({
  serial,
  onPick,
}: {
  serial: string | null
  onPick: (packageId: string) => void
}) {
  const { apps, loading, error } = useQuickBundle(serial)

  if (error !== null) return <Note>{error}</Note>
  if (loading) return <Note>Reading the app list…</Note>
  if (apps.length === 0) return <Note>No user apps are installed on this device.</Note>

  return (
    <QuickList
      rows={apps.map((app) => ({ id: app.packageId, title: app.displayName }))}
      onPick={onPick}
    />
  )
}

function Note({ children }: { children: React.ReactNode }) {
  return <p className="px-2 py-8 text-center text-text-tertiary">{children}</p>
}
