import { useEffect, useState } from "react"

import { listRoles } from "@/lib/daemon"
import type { RoleCatalogue } from "@/lib/roles"

/**
 * The role picker's catalogue, from the daemon.
 *
 * Null until it arrives — and null *forever* if it does not, which is
 * deliberate: the picker is a nicety, and a first launch that showed an empty
 * one because a route failed would be worse than a first launch that went
 * straight to the app. Nothing here retries for the same reason; Settings ▸
 * General can open the picker again once the daemon is answering.
 */
export function useRoleCatalogue(): RoleCatalogue | null {
  const [catalogue, setCatalogue] = useState<RoleCatalogue | null>(null)

  useEffect(() => {
    let live = true
    void listRoles()
      .then((answer) => {
        if (live) setCatalogue(answer)
      })
      .catch(() => {
        // A daemon too old to know the route, or one that is not up yet.
      })
    return () => {
      live = false
    }
  }, [])

  return catalogue
}
