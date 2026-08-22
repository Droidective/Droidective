import { RefreshCw } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { HubColumn, HubSection, IconButton, SwitchRow } from "@/components/Hub"
import { NoDevice } from "@/components/screen"
import { useRestrictions } from "@/hooks/useDeviceSettings"
import type { Device, RestrictionKey, RestrictionsResponse } from "@/lib/wire"

/**
 * The restrictions that are plain booleans on the wire.
 *
 * Narrower than `RestrictionKey` on purpose: `selinuxEnforcing` can be null —
 * `getenforce` may say neither — and that row is rendered separately with its
 * own default, so keeping it out of this union is what stops the two being
 * treated the same by accident.
 */
type PlainRestrictionKey = Exclude<RestrictionKey, "selinuxEnforcing">

/** The Mac's four no-root rows, in its order and with its wording. */
const ROWS: { key: PlainRestrictionKey; title: string }[] = [
  { key: "adbInstallVerification", title: "Verify apps installed via ADB" },
  { key: "packageVerifier", title: "Package verifier" },
  { key: "hiddenApiEnforced", title: "Enforce hidden-API restrictions" },
  { key: "stayAwake", title: "Stay awake while charging" },
]

/**
 * Dev-time system restrictions — the Mac's `SystemRestrictionsView`.
 *
 * Two sections: the install and API toggles, which are plain global settings,
 * and a Root section that only offers anything on a device with a granted `su`
 * shell. Without one it says so in a line of muted text rather than showing
 * controls that would fail — which is why `hasRootShell` rides along with the
 * read instead of being a second request.
 */
export function RestrictionsPane({ device }: { device: Device | null }) {
  const { state, error, busy, refresh, toggle, remount } = useRestrictions(device?.serial ?? null)

  if (!device) return <NoDevice feature="system-restrictions" title="System Restrictions" />

  if (state === null) {
    return (
      <div className="flex h-full flex-col gap-3 p-5">
        {error === null ? (
          <p className="text-text-tertiary">Reading current settings…</p>
        ) : (
          <Banner tone="error">{error.message}</Banner>
        )}
      </div>
    )
  }

  return (
    <HubColumn>
      {error === null ? null : <Banner tone="error">{error.message}</Banner>}

      <HubSection
        title="Installs & APIs"
        accessory={
          <IconButton
            icon={<RefreshCw size={13} />}
            label="Refresh"
            onClick={refresh}
            disabled={busy}
          />
        }
      >
        {ROWS.map((row) => (
          <SwitchRow
            key={row.key}
            title={row.title}
            checked={state[row.key]}
            onChange={(on) => {
              toggle(row.key, on)
            }}
          />
        ))}
      </HubSection>

      <RootSection state={state} busy={busy} onToggle={toggle} onRemount={remount} />
    </HubColumn>
  )
}

function RootSection({
  state,
  busy,
  onToggle,
  onRemount,
}: {
  state: RestrictionsResponse
  busy: boolean
  onToggle: (key: RestrictionKey, on: boolean) => void
  onRemount: () => void
}) {
  return (
    <HubSection title="Root">
      {state.hasRootShell ? (
        <>
          <SwitchRow
            title="SELinux enforcing"
            // The Mac defaults an unknown mode to enforcing rather than showing
            // it as permissive: claiming a device is permissive when
            // `getenforce` would not say is the more dangerous of the two.
            checked={state.selinuxEnforcing ?? true}
            onChange={(on) => {
              onToggle("selinuxEnforcing", on)
            }}
          />
          <div>
            <Button onClick={onRemount} disabled={busy}>
              Remount /system read-write
            </Button>
          </div>
        </>
      ) : (
        <p className="text-text-tertiary">
          Connect a rooted device to relax SELinux or remount the system partition.
        </p>
      )}
    </HubSection>
  )
}
