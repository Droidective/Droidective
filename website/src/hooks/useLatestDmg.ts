import { useEffect, useState } from "react"

import { LATEST_RELEASE_URL } from "@/lib/content"

/**
 * Resolves the latest release's .dmg from the same-origin appcast.xml the
 * release pipeline publishes (no api.github.com — that's rate-limited and
 * often blocked by extensions). Falls back to the GitHub /releases/latest
 * page until (or if) the fetch resolves.
 */
export function useLatestDmg(): string {
  const [url, setUrl] = useState(LATEST_RELEASE_URL)

  useEffect(() => {
    let cancelled = false
    fetch("/appcast.xml", { headers: { Accept: "application/xml" } })
      .then((r) => (r.ok ? r.text() : Promise.reject(new Error(`appcast fetch failed: ${r.status}`))))
      .then((xml) => {
        const doc = new DOMParser().parseFromString(xml, "application/xml")
        const best = Array.from(doc.querySelectorAll("item"))
          .map((item) => {
            const enclosure = item.querySelector("enclosure")
            const versionEl = item.getElementsByTagName("sparkle:version")[0]
            return {
              url: enclosure?.getAttribute("url") ?? null,
              version: versionEl ? Number.parseInt(versionEl.textContent ?? "", 10) || 0 : 0,
            }
          })
          .filter((x): x is { url: string; version: number } => x.url !== null && x.url.toLowerCase().endsWith(".dmg"))
          .sort((a, b) => b.version - a.version)[0]
        if (best && !cancelled) setUrl(best.url)
      })
      .catch(() => {
        /* keep the /releases/latest fallback */
      })
    return () => {
      cancelled = true
    }
  }, [])

  return url
}
