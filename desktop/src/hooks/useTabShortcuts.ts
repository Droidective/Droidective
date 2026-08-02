import { useEffect } from "react"
import { hasModifier } from "@/lib/platform"

/**
 * The tab strip's own keys: close the active tab, and jump to one by position.
 *
 * Per-feature hotkeys are a separate thing this app has yet to grow; these
 * belong to the strip, and a strip you can only click is not one.
 */
export function useTabShortcuts({
  activeTab,
  onClose,
  onActivateIndex,
  onSplit,
  onPalette,
}: {
  activeTab: string | null
  onClose: (id: string) => void
  onActivateIndex: (index: number) => void
  onSplit: (id: string) => void
  onPalette: () => void
}): void {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!hasModifier(event) || event.altKey) return
      if (event.key === "k" || event.key === "t") {
        event.preventDefault()
        onPalette()
        return
      }
      if (event.key === "w") {
        event.preventDefault()
        if (activeTab !== null) onClose(activeTab)
        return
      }
      // Backslash, not D. Ctrl+D is end-of-input in every Linux shell, and a
      // Terminal feature is on the way; this is the split editor binding
      // people already have in their fingers from VS Code, and it is the same
      // physical key on all three platforms.
      if (event.key === "\\") {
        event.preventDefault()
        if (activeTab !== null) onSplit(activeTab)
        return
      }
      // ⌘1–⌘9 / Ctrl+1–9. Read as a single character rather than parsed, so a
      // keyboard that sends "10" or "١" cannot land on an unintended tab.
      if (event.key < "1" || event.key > "9" || event.key.length !== 1) return
      event.preventDefault()
      onActivateIndex(Number(event.key) - 1)
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [activeTab, onClose, onActivateIndex, onSplit, onPalette])
}
