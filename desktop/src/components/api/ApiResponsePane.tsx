import { useState } from "react"
import { Send, TriangleAlert } from "lucide-react"

import { EmptyNote } from "@/components/api/ApiKit"
import { ApiResponseBody } from "@/components/api/ApiResponseBody"
import { ApiResponseDetails } from "@/components/api/ApiResponseDetails"
import { ApiStatusBar } from "@/components/api/ApiStatusBar"
import { Button } from "@/components/Controls"
import type { ApiSendResponse } from "@/lib/daemon"
import { cn } from "@/lib/cn"

type ResponseTab = "body" | "headers" | "cookies" | "timing"

const TABS: { id: ResponseTab; label: string }[] = [
  { id: "body", label: "Body" },
  { id: "headers", label: "Headers" },
  { id: "cookies", label: "Cookies" },
  { id: "timing", label: "Timing" },
]

/** The response half — the Mac's `ApiResponsePane`. */
export function ApiResponsePane({
  response,
  errorText,
  sending,
  canSend,
  onRetry,
  onSaveBody,
}: {
  response: ApiSendResponse | null
  errorText: string | null
  sending: boolean
  canSend: boolean
  onRetry: () => void
  onSaveBody: (response: ApiSendResponse) => void
}) {
  const [tab, setTab] = useState<ResponseTab>("body")
  const [raw, setRaw] = useState(false)
  const [wraps, setWraps] = useState(true)

  if (response === null) {
    if (errorText !== null) {
      return (
        <div className="flex h-full flex-col items-center justify-center gap-3 p-6 text-center">
          <TriangleAlert size={26} className="text-danger" />
          <p data-selectable className="text-[13px] text-danger">
            {errorText}
          </p>
          <Button onClick={onRetry} disabled={!canSend}>
            Try Again
          </Button>
        </div>
      )
    }
    if (sending) return <EmptyNote title="Sending…" />
    return (
      <div className="flex h-full flex-col items-center justify-center gap-2 p-6 text-center">
        <Send size={26} className="text-text-tertiary" />
        <p className="text-[13px] text-text-secondary">Enter a URL and press Send (⌘⏎)</p>
        <p className="text-[12px] text-text-tertiary">
          Pasting a cURL command into the URL field imports it.
        </p>
      </div>
    )
  }

  const failed = response.assertions.filter((one) => !one.passed).length

  return (
    <div className="flex h-full min-h-0 flex-col bg-bg-surface/30">
      <ApiStatusBar
        response={response}
        raw={raw}
        tabs={TABS}
        tab={tab}
        onTab={setTab}
        onSaveBody={onSaveBody}
      />
      <div className="h-px bg-border-subtle" />

      {response.assertions.length === 0 ? null : (
        <div
          className={cn(
            "flex items-center gap-2 px-2.5 py-1 text-[12px]",
            failed === 0 ? "bg-accent/10" : "bg-danger/10",
          )}
        >
          <span className="text-text-primary">
            {response.assertions.length - failed} passed · {failed} failed
          </span>
          {failed > 0 ? (
            <span className="ml-auto truncate text-[11px] text-text-tertiary">
              {response.assertions.find((one) => !one.passed)?.label}
            </span>
          ) : null}
        </div>
      )}

      {tab === "body" ? (
        <ApiResponseBody
          response={response}
          raw={raw}
          onRaw={setRaw}
          wraps={wraps}
          onWraps={setWraps}
          onSaveBody={onSaveBody}
        />
      ) : (
        <ApiResponseDetails tab={tab} response={response} />
      )}
    </div>
  )
}
