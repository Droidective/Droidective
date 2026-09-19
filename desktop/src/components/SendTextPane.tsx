import { Send } from "lucide-react"
import { useState } from "react"
import { Button, TextInput } from "@/components/Controls"
import { NoDevice } from "@/components/NoDevice"
import { SnippetCreator } from "@/components/SnippetCreator"
import { SnippetLibrary } from "@/components/SnippetLibrary"
import { useNotifications } from "@/hooks/useNotifications"
import { useSnippets } from "@/hooks/useSnippets"
import { asDaemonError, runAction } from "@/lib/daemon"
import type { Device } from "@/lib/wire"

/**
 * Send Text — the Mac's `SendTextView`.
 *
 * Two sections, as it has: the send flow at the top, and one recency-ranked
 * snippet library below it. `send-text` stays a `formAction` in the registry,
 * so the palette and the Quick Actions panel still render it from its fields;
 * this is the screen that adds the snippets.
 */
export function SendTextPane({ device }: { device: Device | null }) {
  const [text, setText] = useState("")
  const [query, setQuery] = useState("")
  const [creating, setCreating] = useState(false)
  const snippets = useSnippets()

  if (device === null) return <NoDevice feature="send-text" title="Send Text" />

  return (
    <div className="flex h-full flex-col gap-4 overflow-auto p-4">
      <SendRow device={device} text={text} onText={setText} />

      <SnippetLibrary
        snippets={snippets}
        query={query}
        onQuery={setQuery}
        onNew={() => {
          setCreating(true)
        }}
        onInsert={(expanded) => {
          setText((current) => current + expanded)
        }}
      />

      {creating ? (
        <SnippetCreator
          existing={snippets.all}
          initialText={text}
          onCancel={() => {
            setCreating(false)
          }}
          onSave={async (name, snippetText) => {
            const saved = await snippets.add(name, snippetText)
            if (saved) setCreating(false)
            return saved
          }}
        />
      ) : null}
    </div>
  )
}

/** The send flow: a field, a Send button, and ⏎. */
function SendRow({
  device,
  text,
  onText,
}: {
  device: Device
  text: string
  onText: (text: string) => void
}) {
  const [sending, setSending] = useState(false)
  const { show } = useNotifications()

  const send = () => {
    if (text === "" || sending) return
    setSending(true)
    void runAction({ featureId: "send-text", serial: device.serial, fields: { text } })
      .then((result) => {
        show({ message: result.message, ok: result.ok })
      })
      .catch((thrown: unknown) => {
        show({ message: asDaemonError(thrown).message, ok: false })
      })
      .finally(() => {
        setSending(false)
      })
  }

  return (
    <section className="flex flex-col gap-2">
      <h2 className="text-[13px] font-medium text-text-primary">Send text</h2>
      <div className="flex items-start gap-2">
        <TextInput
          value={text}
          onChange={onText}
          placeholder="Type or paste text to send…"
          onKeyDown={(event) => {
            if (event.key === "Enter") send()
          }}
        />
        <Button tone="primary" disabled={text === "" || sending} onClick={send}>
          <Send size={13} /> Send
        </Button>
      </div>
      <p className="text-[11.5px] text-text-tertiary">⏎ to send</p>
    </section>
  )
}
