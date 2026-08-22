import { useCallback, useEffect, useState } from "react"
import { useNotifications } from "@/hooks/useNotifications"
import { useTargets } from "@/hooks/useTargets"
import { asDaemonError, deepLinks, launchDeepLink, writeDeepLinks } from "@/lib/daemon"
import { launchSummary, removeLink, upsert } from "@/lib/deeplinks"
import type { DaemonError, DeepLink } from "@/lib/wire"

export interface DeepLinksController {
  links: DeepLink[]
  error: DaemonError | null
  /** False when nothing is targeted, which is what greys out Launch. */
  canLaunch: boolean
  save: (link: DeepLink) => void
  remove: (link: DeepLink) => void
  launch: (link: DeepLink) => void
}

/**
 * One app's links, and the three things that happen to them.
 *
 * The list is read from the daemon's store — the same file the Mac writes — and
 * every edit writes the whole list back for that one package id. Optimistic on
 * screen and then reconciled with what was stored: the file is the truth, and a
 * write that failed must not leave the screen showing something that is not in
 * it.
 */
export function useDeepLinks(packageId: string | null): DeepLinksController {
  const { show } = useNotifications()
  const { serials } = useTargets()
  const [links, setLinks] = useState<DeepLink[]>([])
  const [error, setError] = useState<DaemonError | null>(null)

  const load = useCallback(async () => {
    if (packageId === null) {
      setLinks([])
      return
    }
    setError(null)
    try {
      const response = await deepLinks(packageId)
      setLinks(response.links)
    } catch (thrown) {
      setError(asDaemonError(thrown))
    }
  }, [packageId])

  useEffect(() => {
    void load()
  }, [load])

  const persist = (next: DeepLink[]) => {
    if (packageId === null) return
    setLinks(next)
    void (async () => {
      try {
        const stored = await writeDeepLinks(packageId, next)
        setLinks(stored.links)
      } catch (thrown) {
        show({ message: asDaemonError(thrown).message, ok: false })
        void load()
      }
    })()
  }

  return {
    links,
    error,
    canLaunch: serials.length > 0,
    save: (link: DeepLink) => {
      persist(upsert(links, link))
    },
    remove: (link: DeepLink) => {
      persist(removeLink(links, link.id))
    },
    launch: (link: DeepLink) => {
      void (async () => {
        try {
          const response = await launchDeepLink(serials, link.url)
          const summary = launchSummary(response.outcomes)
          show({ message: summary.message, ok: summary.ok })
        } catch (thrown) {
          show({ message: asDaemonError(thrown).message, ok: false })
        }
      })()
    },
  }
}
