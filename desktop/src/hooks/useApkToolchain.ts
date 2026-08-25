import { useEffect, useState } from "react"

import { apkToolchain } from "@/lib/daemon"
import type { ApkToolchain } from "@/lib/wire"

/**
 * Which of the APK tools this machine has.
 *
 * Asked when a screen opens rather than when a run fails: the SDK build-tools
 * are *detected*, not downloadable, so "install the build-tools" is advice
 * someone can act on before they pick a file. After a failed run the same
 * message reads as though their APK was the problem.
 */
export function useApkToolchain(): ApkToolchain | null {
  const [tools, setTools] = useState<ApkToolchain | null>(null)

  useEffect(() => {
    let cancelled = false
    apkToolchain().then(
      (answer) => {
        if (!cancelled) setTools(answer)
      },
      () => {
        // A daemon that cannot answer is already surfaced by the screen's own
        // first call; a second error here would say the same thing twice.
      },
    )
    return () => {
      cancelled = true
    }
  }, [])

  return tools
}

/** The tools a feature needs that this machine does not have. */
export function missingTools(
  tools: ApkToolchain | null,
  needed: (keyof ApkToolchain)[],
): string[] {
  if (tools === null) return []
  return needed.filter((tool) => !tools[tool])
}
