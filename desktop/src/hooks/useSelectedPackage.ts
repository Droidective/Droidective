import { useEffect, useState } from "react"

/**
 * The chosen app, and the rule that it does not survive a device change.
 *
 * Owned by the window rather than by a pane, because two halves of the chrome
 * read it: the panes that act on an app, and the device bar's app pill that
 * changes it. Dropped on a new selection because a package id means nothing on
 * a different device — carrying it over would silently target an app that may
 * not be installed there.
 */
export function useSelectedPackage(
  serial: string | null,
): [string | null, (packageId: string | null) => void] {
  const [packageId, setPackageId] = useState<string | null>(null)
  useEffect(() => {
    setPackageId(null)
  }, [serial])
  return [packageId, setPackageId]
}
