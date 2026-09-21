import { useEffect } from "react"

import { hasModifier } from "@/lib/platform"

/**
 * The two keys the request bar's tooltips promise.
 *
 * They promised them before anything bound them: the bar said "Send (⌘⏎)" and
 * "Save this request (⌘S)" on a build that runs only on Windows and Linux, so
 * the glyph named a key the host does not have *and* neither chord did
 * anything. The Mac binds both, which is why this exists rather than the
 * tooltips being trimmed.
 *
 * Not while a text field has focus for Save — Ctrl+S there is still the
 * request's, since there is nothing else it could mean — but Enter is: a bare
 * Enter in the URL field already sends, and the modifier version has to work
 * from anywhere in the pane.
 */
export function useApiShortcuts(args: {
  onSend: () => void
  onSave: () => void
  canSend: boolean
  canSave: boolean
}): void {
  const { onSend, onSave, canSend, canSave } = args
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!hasModifier(event) || event.shiftKey || event.altKey) return
      if (event.key === "Enter" && canSend) {
        event.preventDefault()
        onSend()
        return
      }
      if (event.key === "s" && canSave) {
        event.preventDefault()
        onSave()
      }
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onSend, onSave, canSend, canSave])
}
