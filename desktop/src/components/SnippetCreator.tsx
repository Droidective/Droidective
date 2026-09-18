import { useState } from "react"
import { Button, TextInput } from "@/components/Controls"
import { PlaceholderChips } from "@/components/SnippetList"
import { NAME_LIMIT, nameProblem, type Snippet } from "@/lib/snippets"

/**
 * Saving a snippet — the Mac's one creator, reached from the New Snippet
 * button and nowhere else.
 *
 * It opens on whatever is already typed into the send field, because the
 * common way to make a snippet is to have just typed the thing again.
 */
export function SnippetCreator({
  existing,
  initialText,
  onCancel,
  onSave,
}: {
  existing: readonly Snippet[]
  initialText: string
  onCancel: () => void
  onSave: (name: string, text: string) => Promise<boolean>
}) {
  const [name, setName] = useState("")
  const [text, setText] = useState(initialText)
  const [saving, setSaving] = useState(false)

  const problem = nameProblem(name, existing)
  const canSave = problem === null && text !== "" && !saving

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      <button
        type="button"
        aria-label="Cancel"
        onClick={onCancel}
        className="absolute inset-0 cursor-default"
      />
      <div className="relative flex w-[440px] max-w-full flex-col gap-3 rounded-xl border border-border-subtle bg-bg-raised p-4 shadow-2xl">
        <h2 className="text-[14px] font-medium text-text-primary">New snippet</h2>
        <TextInput
          value={name}
          onChange={setName}
          placeholder="Name — shown in the list"
          ariaLabel="Snippet name"
        />
        <TextInput
          value={text}
          onChange={setText}
          placeholder="Text to insert…"
          ariaLabel="Snippet text"
        />
        <PlaceholderChips
          onAppend={(token) => {
            setText((current) => current + token)
          }}
        />
        <div className="flex items-center gap-2">
          <span className="flex-1 text-[11.5px] text-text-tertiary">
            {name.length}/{NAME_LIMIT}
          </span>
          <Button onClick={onCancel}>Cancel</Button>
          <Button
            tone="primary"
            disabled={!canSave}
            onClick={() => {
              setSaving(true)
              void onSave(name, text).finally(() => {
                setSaving(false)
              })
            }}
          >
            Save
          </Button>
        </div>
        {name === "" || problem === null ? null : (
          <p className="text-[11.5px] text-danger">{problem}</p>
        )}
      </div>
    </div>
  )
}
