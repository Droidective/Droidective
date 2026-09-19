import { Plus } from "lucide-react"
import { Button, TextInput } from "@/components/Controls"
import { SnippetList } from "@/components/SnippetList"
import type { Snippets } from "@/hooks/useSnippets"
import { filtered } from "@/lib/snippets"

/** The snippet library — the Mac's second section. */
export function SnippetLibrary({
  snippets,
  query,
  onQuery,
  onNew,
  onInsert,
}: {
  snippets: Snippets
  query: string
  onQuery: (query: string) => void
  onNew: () => void
  onInsert: (expanded: string) => void
}) {
  const visible = filtered(snippets.ranked, query)
  return (
    <section className="flex min-h-0 flex-col gap-2">
      <header className="flex items-center gap-2">
        <h2 className="flex-1 text-[13px] font-medium text-text-primary">Snippets</h2>
        <Button onClick={onNew}>
          <Plus size={13} /> New Snippet
        </Button>
      </header>
      <p className="text-[11.5px] text-text-tertiary">
        Click one to insert it — {"{clipboard}"} and {"{ip}"} fill in with the live value.
      </p>
      {snippets.all.length === 0 ? null : (
        <TextInput value={query} onChange={onQuery} placeholder="Search snippets…" />
      )}
      {snippets.error === null ? null : (
        <p className="text-[12px] text-danger">{snippets.error.message}</p>
      )}
      {snippets.all.length === 0 ? (
        <p className="py-6 text-center text-text-tertiary">
          No snippets yet. Save the text you type often and it’s one click from here.
        </p>
      ) : visible.length === 0 ? (
        <p className="py-6 text-center text-text-tertiary">No snippets match “{query}”.</p>
      ) : (
        <SnippetList
          snippets={visible}
          onInsert={(snippet) => {
            void snippets.insert(snippet).then(onInsert)
          }}
          onRemove={(snippet) => {
            void snippets.remove(snippet.name)
          }}
        />
      )}
    </section>
  )
}
