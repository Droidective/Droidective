import { Trash2 } from "lucide-react"
import { IconButton } from "@/components/Hub"
import { PLACEHOLDERS, type Snippet } from "@/lib/snippets"

/**
 * One list of saved snippets, shared by the Send Text screen and the Quick
 * Actions panel.
 *
 * The Mac's two lists differ in exactly two ways and both are props here: the
 * panel has no remove button (it is not a place to curate from) and it walks
 * rows with ↓/↑, so a row can be highlighted without being hovered.
 */
export function SnippetList({
  snippets,
  highlighted = -1,
  onInsert,
  onRemove,
}: {
  snippets: readonly Snippet[]
  /** Index of the row the keyboard is on, or -1. */
  highlighted?: number
  onInsert: (snippet: Snippet) => void
  onRemove?: ((snippet: Snippet) => void) | undefined
}) {
  return (
    <ul className="flex flex-col">
      {snippets.map((snippet, index) => (
        <li
          key={snippet.name}
          className={
            index === highlighted
              ? "flex items-center gap-2 rounded-md bg-accent/[0.14] px-2 py-1.5"
              : "flex items-center gap-2 rounded-md px-2 py-1.5 hover:bg-white/[0.04]"
          }
        >
          <button
            type="button"
            onClick={() => {
              onInsert(snippet)
            }}
            className="flex min-w-0 flex-1 items-baseline gap-2 text-left"
          >
            <span className="shrink-0 rounded bg-bg-raised px-1.5 py-0.5 text-[11.5px] text-text-primary">
              {snippet.name}
            </span>
            <span className="min-w-0 flex-1 truncate text-[12px] text-text-tertiary">
              {snippet.text}
            </span>
          </button>
          {onRemove === undefined ? null : (
            <IconButton
              icon={<Trash2 size={13} />}
              label={`Remove ${snippet.name}`}
              onClick={() => {
                onRemove(snippet)
              }}
            />
          )}
        </li>
      ))}
    </ul>
  )
}

/**
 * The `{clipboard}` / `{ip}` chips, which append to whatever is being typed.
 *
 * Click-to-append rather than a menu, as the Mac's creator does: they are two
 * short tokens and a menu to insert two things is a menu too many.
 */
export function PlaceholderChips({ onAppend }: { onAppend: (token: string) => void }) {
  return (
    <div className="flex items-center gap-1.5">
      <span className="text-[11.5px] text-text-tertiary">Add a live value:</span>
      {PLACEHOLDERS.map((name) => (
        <button
          key={name}
          type="button"
          onClick={() => {
            onAppend(`{${name}}`)
          }}
          className="rounded bg-bg-raised px-1.5 py-0.5 font-mono text-[11.5px] text-text-primary transition hover:bg-border-subtle"
        >
          {`{${name}}`}
        </button>
      ))}
    </div>
  )
}
