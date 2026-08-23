import { createContext, useContext, useEffect, useMemo, useRef } from "react"
import { invoke } from "@tauri-apps/api/core"
import type { SplitDirection } from "@/lib/terminal"

/** What the menu can ask of whichever Terminal pane is mounted. */
export interface TerminalCommands {
  newTab: () => void
  split: (direction: SplitDirection) => void
  closeFocused: () => void
  renameFocused: () => void
  cycle: (by: 1 | -1) => void
}

/**
 * A slot the Terminal pane fills while it is mounted.
 *
 * A ref rather than state, deliberately: the menu reads it at *click* time, so
 * nothing above needs to re-render when a terminal appears or goes away — and a
 * re-render there would reach every mounted shell, which is exactly what
 * `TerminalShell` goes to some trouble to avoid.
 *
 * This is the shape of `AppState.terminals` on the Mac — nil when no terminal is
 * open — reached the way this app reaches shared state everywhere else, through
 * a context.
 */
const TerminalCommandsContext = createContext<{ current: TerminalCommands | null }>({
  current: null,
})

export function TerminalCommandsProvider({ children }: { children: React.ReactNode }) {
  const slot = useRef<TerminalCommands | null>(null)
  // A stable object: the ref is the mutable part, so this never needs to change
  // identity and can never re-render the tree below it.
  const value = useMemo(() => slot, [])
  return (
    <TerminalCommandsContext.Provider value={value}>{children}</TerminalCommandsContext.Provider>
  )
}

/**
 * Registers the mounted Terminal pane, and tells the native menu whether its
 * terminal commands have anything to act on.
 *
 * The menu greys them out otherwise, as the Mac's
 * `.disabled(!terminalCommandsEnabled)` does — a menu offering "Split Terminal"
 * with no terminal open is a menu that lies.
 */
export function useRegisterTerminalCommands(commands: TerminalCommands): void {
  const slot = useContext(TerminalCommandsContext)
  slot.current = commands
  useEffect(() => {
    void invoke("set_terminal_commands_enabled", { enabled: true }).catch(ignore)
    return () => {
      slot.current = null
      void invoke("set_terminal_commands_enabled", { enabled: false }).catch(ignore)
    }
  }, [slot])
}

/** The mounted pane's commands, or null when the Terminal is not open. */
export function useTerminalCommands(): { current: TerminalCommands | null } {
  return useContext(TerminalCommandsContext)
}

/** A menu-state update the window lost the race with is not worth reporting. */
function ignore() {}
