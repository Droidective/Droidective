import { useCallback, useState } from "react"

import { linkCutQuestion, type LinkCutQuestion } from "@/lib/tailnet"
import type { Device, FeatureSummary } from "@/lib/wire"

export interface LinkGuard {
  /** The question showing, while a run waits for its second press. */
  warning: LinkCutQuestion | null
  /** Run `proceed` now, or arm on the first press when it would cut a tailnet link. */
  guard: (feature: FeatureSummary, serials: string[], proceed: () => void) => void
  clearWarning: () => void
}

/**
 * The Quick Actions panel's link-cut question — the Mac panel's, which arms
 * rather than asking in a dialog because a panel that never takes focus cannot
 * hold one.
 *
 * A feature that can take a phone off the network, run on one reached over
 * Tailscale, arms on the first press and shows the question; a second press
 * for the *same* feature and devices runs it. Keyed on both, so arming one
 * phone is never consent for another.
 */
export function useQuickLinkGuard(ready: readonly Device[]): LinkGuard {
  const [armed, setArmed] = useState<{ key: string; question: LinkCutQuestion } | null>(null)

  const guard = useCallback(
    (feature: FeatureSummary, serials: string[], proceed: () => void) => {
      const question = linkCutQuestion(feature.remoteLinkWarning, serials, ready)
      const key = `${feature.id}|${serials.join(",")}`
      if (question === null || armed?.key === key) {
        setArmed(null)
        proceed()
        return
      }
      setArmed({ key, question })
    },
    [ready, armed],
  )

  const clearWarning = useCallback(() => {
    setArmed(null)
  }, [])

  return { warning: armed?.question ?? null, guard, clearWarning }
}
