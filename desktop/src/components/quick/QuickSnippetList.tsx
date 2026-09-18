import { useEffect, useState } from "react"
import { SnippetList } from "@/components/SnippetList"
import { useSnippets } from "@/hooks/useSnippets"
import { moveHighlight, panelSplit } from "@/lib/snippets"

/**
 * The saved snippets, under the panel's Send Text field — the Mac's
 * `QuickSnippetList`.
 *
 * ↓/↑ walk it and ⏎ inserts the highlighted one, while ⌘⏎ still runs the form;
 * the top five show and the rest sit behind "Show N more". The ranking is the
 * main window's, because it is the same store.
 *
 * **No search field.** The panel's one text field holds the text being *sent*,
 * and filtering the list by it would hide the snippet somebody was reaching
 * for the moment they started typing the thing they wanted to replace.
 */
export function QuickSnippetList({ onInsert }: { onInsert: (text: string) => void }) {
  const snippets = useSnippets()
  const [expanded, setExpanded] = useState(false)
  const [highlighted, setHighlighted] = useState(-1)
  const { shown, hidden } = panelSplit(snippets.all, expanded)

  // ↓/↑ and ⏎ are handled on the window, because the caret stays in the form's
  // field: a list that stole focus would stop someone typing mid-thought.
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault()
        setHighlighted((current) =>
          moveHighlight(current, event.key === "ArrowDown" ? 1 : -1, shown.length),
        )
        return
      }
      // ⌘⏎ belongs to the form's Run; a bare ⏎ with a row picked inserts it.
      if (event.key !== "Enter" || event.metaKey || event.ctrlKey) return
      const picked = shown[highlighted]
      if (picked === undefined) return
      event.preventDefault()
      void snippets.insert(picked).then(onInsert)
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [highlighted, onInsert, shown, snippets])

  if (snippets.all.length === 0) return null

  return (
    <div className="flex flex-col gap-1 border-t border-border-subtle pt-2">
      <span className="text-[11.5px] text-text-tertiary">Snippets</span>
      <SnippetList
        snippets={shown}
        highlighted={highlighted}
        onInsert={(snippet) => {
          void snippets.insert(snippet).then(onInsert)
        }}
      />
      {hidden === 0 ? null : (
        <button
          type="button"
          onClick={() => {
            setExpanded(true)
          }}
          className="self-start px-2 py-1 text-[11.5px] text-text-tertiary transition hover:text-text-primary"
        >
          Show {hidden} more
        </button>
      )}
    </div>
  )
}
