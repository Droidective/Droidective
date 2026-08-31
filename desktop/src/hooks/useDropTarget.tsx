import { createContext, useCallback, useContext, useMemo, useRef, useState } from "react"

/**
 * Where a dropped file would land, published by the screen that knows.
 *
 * The drop listener is on the window — it has to be, or a file dropped on the
 * sidebar would go nowhere — but the destination is inside a tab. The File
 * Explorer registers the directory it is showing, exactly as the Terminal pane
 * registers its commands, and the shell reads it when a drop arrives.
 *
 * A tab that is merely *open* must not register: a hidden keep-alive explorer
 * would otherwise claim every drop while a different screen is on top.
 */
interface DropTarget {
  directory: string | null
  /** Called by the File Explorer while it is the visible tab. */
  register: (directory: string | null) => void
}

const DropTargetContext = createContext<DropTarget | null>(null)

export function DropTargetProvider({ children }: { children: React.ReactNode }) {
  const [directory, setDirectory] = useState<string | null>(null)
  // The registering pane re-renders as its listing loads; writing the same
  // path again would put the whole shell through an update for nothing.
  const last = useRef<string | null>(null)

  const register = useCallback((next: string | null) => {
    if (last.current === next) return
    last.current = next
    setDirectory(next)
  }, [])

  const value = useMemo(() => ({ directory, register }), [directory, register])
  return <DropTargetContext value={value}>{children}</DropTargetContext>
}

/** Nothing to publish to, and nothing dropped can reach here. */
const outsideProvider: DropTarget = {
  directory: null,
  register: () => {
    // Deliberately nothing: there is no window drop listener to tell.
  },
}

export function useDropTarget(): DropTarget {
  const target = useContext(DropTargetContext)
  // Null outside the provider rather than a throw: the Quick Actions panel
  // renders some of the same components and has no drop target at all.
  return target ?? outsideProvider
}
