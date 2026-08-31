import { Copy, WrapText } from "lucide-react"

import { EmptyNote, IconButton } from "@/components/api/ApiKit"
import { Button } from "@/components/Controls"
import { copyText, type ApiSendResponse } from "@/lib/daemon"
import { cn } from "@/lib/cn"

/**
 * The response body, and the bar above it.
 *
 * The bar stays put for every textual body — not only the ones with a pretty
 * form — so wrapping and copying do not come and go with the content type.
 */

export function ApiResponseBody({
  response,
  raw,
  onRaw,
  wraps,
  onWraps,
  onSaveBody,
}: {
  response: ApiSendResponse
  raw: boolean
  onRaw: (raw: boolean) => void
  wraps: boolean
  onWraps: (wraps: boolean) => void
  onSaveBody: (response: ApiSendResponse) => void
}) {
  const text = displayText(response, raw)

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      {text === null ? null : (
        <div className="flex items-center gap-2 px-2 py-1">
          {response.prettyBody === null ? null : (
            <span className="flex gap-1">
              {[
                { label: "Pretty", value: false },
                { label: "Raw", value: true },
              ].map((one) => (
                <button
                  key={one.label}
                  type="button"
                  onClick={() => {
                    onRaw(one.value)
                  }}
                  className={cn(
                    "rounded px-2 py-0.5 text-[12px]",
                    raw === one.value
                      ? "bg-bg-raised text-text-primary"
                      : "text-text-secondary hover:text-text-primary",
                  )}
                >
                  {one.label}
                </button>
              ))}
            </span>
          )}
          <IconButton
            label={wraps ? "Wrap long lines (on)" : "Wrap long lines (off)"}
            onClick={() => {
              onWraps(!wraps)
            }}
          >
            <WrapText size={13} className={wraps ? "text-accent" : undefined} />
          </IconButton>
          <IconButton
            label="Copy the body as shown"
            onClick={() => {
              void copyText(text)
            }}
          >
            <Copy size={13} />
          </IconButton>
          <span className="ml-auto font-mono text-[11px] text-text-tertiary">
            {response.mediaType === "" ? response.format : response.mediaType}
          </span>
        </div>
      )}
      <BodyContent response={response} text={text} wraps={wraps} onSaveBody={onSaveBody} />
    </div>
  )
}

function BodyContent({
  response,
  text,
  wraps,
  onSaveBody,
}: {
  response: ApiSendResponse
  text: string | null
  wraps: boolean
  onSaveBody: (response: ApiSendResponse) => void
}) {
  if (response.format === "image" && response.bodyBase64 !== null) {
    return (
      <div className="min-h-0 flex-1 overflow-auto p-2">
        <img
          src={`data:${response.mediaType === "" ? "image/png" : response.mediaType};base64,${response.bodyBase64}`}
          alt="Response body"
          className="max-w-full"
        />
      </div>
    )
  }
  if (text !== null) {
    return (
      <pre
        data-selectable
        className={cn(
          "min-h-0 flex-1 overflow-auto p-2 font-mono text-[12px] text-text-primary",
          wraps ? "whitespace-pre-wrap break-words" : "whitespace-pre",
        )}
      >
        {text}
      </pre>
    )
  }
  if (response.size === 0) return <EmptyNote title="No response body." />
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-2 p-4 text-center">
      <p className="text-[12px] text-text-secondary">{response.sizeText} of binary data</p>
      {response.bodyOmitted ? (
        <p className="text-[11px] text-text-tertiary">
          Too large to show here — save it to a file to look at it.
        </p>
      ) : null}
      <Button
        onClick={() => {
          onSaveBody(response)
        }}
        disabled={response.bodyBase64 === null}
      >
        Save to File…
      </Button>
    </div>
  )
}

export function displayText(response: ApiSendResponse, raw: boolean): string | null {
  if (!raw && response.prettyBody !== null) return response.prettyBody
  return response.bodyText
}
