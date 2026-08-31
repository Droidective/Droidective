import { useState } from "react"

import { ApiSheet } from "@/components/api/ApiKit"
import { Button, TextInput } from "@/components/Controls"

/** Every sheet the API pane can raise. Named as the Mac's `ApiClientSheet` is. */
export type ApiSheetKind =
  | { kind: "importCurl" }
  | { kind: "saveRequest" }
  | { kind: "newCollection" }
  | { kind: "renameCollection"; id: string }
  | { kind: "newFolder"; collectionId: string; parent: string | null }
  | { kind: "renameFolder"; collectionId: string; folderId: string }
  | { kind: "collectionAuth"; id: string }
  | { kind: "collectionVariables"; id: string }
  | { kind: "newEnvironment" }
  | { kind: "environment"; id: string }
  | { kind: "globals" }
  | { kind: "runner"; collectionId: string }

/** A one-field prompt — the Mac's `NameSheet`. */
export function NameSheet({
  title,
  placeholder,
  action,
  initial = "",
  onCommit,
  onDismiss,
}: {
  title: string
  placeholder: string
  action: string
  initial?: string
  onCommit: (name: string) => void
  onDismiss: () => void
}) {
  const [text, setText] = useState(initial)
  const commit = () => {
    const trimmed = text.trim()
    if (trimmed === "") return
    onCommit(trimmed)
    onDismiss()
  }

  return (
    <ApiSheet
      title={title}
      width={360}
      onDismiss={onDismiss}
      footer={
        <>
          <Button onClick={onDismiss}>Cancel</Button>
          <Button tone="primary" onClick={commit} disabled={text.trim() === ""}>
            {action}
          </Button>
        </>
      }
    >
      <TextInput
        value={text}
        onChange={setText}
        placeholder={placeholder}
        // The sheet opened because someone asked for it; landing anywhere else
        // would cost a click every time, and the Mac's own sheet focuses its
        // field too.
        // oxlint-disable-next-line jsx-a11y/no-autofocus
        autoFocus
        onKeyDown={(event) => {
          if (event.key === "Enter") commit()
        }}
      />
    </ApiSheet>
  )
}

/**
 * Pasting a cURL command — the Mac's `CurlImportSheet`.
 *
 * The parse is a daemon route: `CurlParser` is a flag table three hundred
 * entries long, and a second implementation would disagree with the first
 * about exactly the commands that are hard to parse.
 */
export function CurlImportSheet({
  onImport,
  onDismiss,
}: {
  onImport: (text: string) => Promise<string | null>
  onDismiss: () => void
}) {
  const [text, setText] = useState("")
  const [failure, setFailure] = useState<string | null>(null)

  return (
    <ApiSheet
      title="Import cURL"
      width={540}
      onDismiss={onDismiss}
      footer={
        <>
          <Button onClick={onDismiss}>Cancel</Button>
          <Button
            tone="primary"
            disabled={text.trim() === ""}
            onClick={() => {
              void onImport(text).then((problem) => {
                if (problem === null) onDismiss()
                else setFailure(problem)
              })
            }}
          >
            Import
          </Button>
        </>
      }
    >
      <p className="text-[12px] text-text-secondary">
        Paste a command copied from a terminal or from your browser&apos;s network tab.
      </p>
      <textarea
        aria-label="cURL command"
        value={text}
        spellCheck={false}
        onChange={(event) => {
          setText(event.target.value)
          setFailure(null)
        }}
        className="min-h-[140px] w-full rounded-md border border-border-subtle bg-bg-root p-2 font-mono text-[12px] text-text-primary outline-none focus:border-accent"
      />
      {failure === null ? null : <p className="text-[12px] text-warn">{failure}</p>}
    </ApiSheet>
  )
}
