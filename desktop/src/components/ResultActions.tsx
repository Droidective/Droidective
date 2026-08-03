import { useEffect, useState } from "react"
import { Check, Clipboard, FolderOpen } from "lucide-react"
import { asDaemonError, copyText, revealPath } from "@/lib/daemon"
import type { RunResponse } from "@/lib/wire"

/**
 * What an action gave back, and what you can do with it.
 *
 * A result carrying `copyText` lands on the clipboard **immediately** — that is
 * the whole point of Copy Device IP, Copy Foreground Bundle ID and Copy Current
 * Activity, and it is what `AppState.show` does on the Mac. It used to render
 * the value and stop there, so the action's name was a promise the UI did not
 * keep.
 *
 * The button is for later: this pane keeps its result on screen, unlike the
 * Mac's toast, so "still on the clipboard?" stops being obvious after you have
 * copied something else.
 */
export function ResultActions({ result }: { result: RunResponse }) {
  const [copied, setCopied] = useState(false)
  const [flash, setFlash] = useState(false)
  const [failure, setFailure] = useState<string | null>(null)

  const text = result.copyText
  useEffect(() => {
    if (text === null) return
    setFailure(null)
    setCopied(false)
    copyText(text)
      .then(() => {
        setCopied(true)
      })
      // Loudly: a copy that quietly does nothing is the defect this replaces.
      .catch((thrown: unknown) => {
        setFailure(asDaemonError(thrown).message)
      })
  }, [text])

  if (text === null && result.revealPath === null) return null

  const recopy = async () => {
    if (text === null) return
    setFailure(null)
    try {
      await copyText(text)
      setCopied(true)
      setFlash(true)
      globalThis.setTimeout(() => {
        setFlash(false)
      }, 1200)
    } catch (thrown) {
      setFailure(asDaemonError(thrown).message)
    }
  }

  const reveal = async (path: string) => {
    setFailure(null)
    try {
      await revealPath(path)
    } catch (thrown) {
      setFailure(asDaemonError(thrown).message)
    }
  }

  return (
    <div className="mt-2 flex flex-wrap items-center gap-2">
      {text === null ? null : (
        <SmallButton icon={copied ? Check : Clipboard} onClick={() => void recopy()}>
          {flash ? "Copied" : copied ? "Copy again" : "Copy"}
        </SmallButton>
      )}
      {result.revealPath === null ? null : (
        <SmallButton icon={FolderOpen} onClick={() => void reveal(result.revealPath ?? "")}>
          Show in folder
        </SmallButton>
      )}
      {copied && failure === null ? (
        <span className="text-text-tertiary">· copied to the clipboard</span>
      ) : null}
      {failure === null ? null : <span className="text-danger">{failure}</span>}
    </div>
  )
}

function SmallButton({
  icon: Icon,
  onClick,
  children,
}: {
  icon: typeof Clipboard
  onClick: () => void
  children: string
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex items-center gap-1.5 rounded-md bg-white/[0.06] px-2 py-1 text-[12px] text-text-primary transition-colors hover:bg-white/[0.12]"
    >
      <Icon size={12} />
      {children}
    </button>
  )
}
