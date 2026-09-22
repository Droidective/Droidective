import { useState } from "react"

import { ConfirmDialog } from "@/components/ConfirmDialog"
import { Button } from "@/components/Controls"
import { HubSection } from "@/components/Hub"
import type { ActiveOverride } from "@/lib/wire"

/**
 * The Mac's destructive button, and what it would clear.
 *
 * Shown only when there is something to reset — the Mac's own rule
 * (`if !state.activeOverrides.isEmpty`), and the reason this needed the
 * reconciled read rather than a local record: a button offering to undo
 * nothing is worse than no button.
 *
 * Naming the kinds is this app's addition: "Reset all overrides" on its own
 * does not say what it will put back, and the read that makes the button
 * appear already knows.
 */
export function ResetOverridesRow({
  overrides,
  busy,
  onReset,
}: {
  overrides: ActiveOverride[]
  busy: boolean
  onReset: () => void
}) {
  const [confirming, setConfirming] = useState(false)
  const named = overrides.map((override) => override.label).join(", ")

  return (
    <HubSection title="Overrides in effect" subtitle={named}>
      <div>
        <Button
          tone="danger"
          disabled={busy}
          onClick={() => {
            setConfirming(true)
          }}
        >
          Reset all overrides
        </Button>
      </div>
      {confirming && (
        <ConfirmDialog
          title="Reset all overrides?"
          message={`${named} go back to what the device had before.`}
          confirmLabel="Reset all overrides"
          onConfirm={() => {
            setConfirming(false)
            onReset()
          }}
          onCancel={() => {
            setConfirming(false)
          }}
        />
      )}
    </HubSection>
  )
}
