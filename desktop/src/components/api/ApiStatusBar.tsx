import { Download } from "lucide-react"

import { ApiMenuButton } from "@/components/api/ApiMenu"
import { displayText } from "@/components/api/ApiResponseBody"
import { statusColor } from "@/lib/api/labels"
import { copyText, type ApiSendResponse } from "@/lib/daemon"
import { cn } from "@/lib/cn"

/**
 * The response's headline row — the Mac's `statusBar`.
 *
 * The tabs sit at the trailing end and take whatever width the metrics leave,
 * which is the arrangement `AdaptiveTabBar` produces there.
 */
export function ApiStatusBar<Tab extends string>({
  response,
  raw,
  tabs,
  tab,
  onTab,
  onSaveBody,
}: {
  response: ApiSendResponse
  /** Which form of the body Copy Everything should carry. */
  raw: boolean
  tabs: { id: Tab; label: string }[]
  tab: Tab
  onTab: (tab: Tab) => void
  onSaveBody: (response: ApiSendResponse) => void
}) {
  return (
    <div className="flex flex-wrap items-center gap-2.5 p-2">
      <span className={cn("font-mono text-[14px] font-medium", statusColor(response.statusCode))}>
        {response.statusCode}
      </span>
      <span className="text-[12px] text-text-secondary">{response.statusText}</span>
      <span className="font-mono text-[12px] text-text-tertiary">
        {Math.round(response.elapsedMs)} ms
      </span>
      <span className="font-mono text-[12px] text-text-tertiary">{response.sizeText}</span>
      {response.truncated ? (
        <span
          className="text-[11px] text-warn"
          title="The body was larger than the per-request limit in Settings."
        >
          truncated
        </span>
      ) : null}
      <ApiMenuButton
        label="Save or copy the response"
        entries={[
          {
            label: "Save Body to File…",
            onSelect: () => {
              onSaveBody(response)
            },
          },
          {
            label: "Copy Everything",
            separatorBefore: true,
            onSelect: () => {
              void copyText(everything(response, raw))
            },
          },
        ]}
      >
        <Download size={13} />
      </ApiMenuButton>

      <span className="ml-auto flex gap-1">
        {tabs.map((one) => (
          <button
            key={one.id}
            type="button"
            onClick={() => {
              onTab(one.id)
            }}
            className={cn(
              "rounded-md px-2 py-1 text-[12px] transition",
              tab === one.id
                ? "bg-bg-raised text-text-primary"
                : "text-text-secondary hover:text-text-primary",
            )}
          >
            {one.label}
          </button>
        ))}
      </span>
    </div>
  )
}

/** One clipboard-friendly dump of the exchange, for pasting into an issue. */
function everything(response: ApiSendResponse, raw: boolean): string {
  const parts = [
    `${String(response.statusCode)} ${response.statusText}` +
      ` · ${String(Math.round(response.elapsedMs))} ms · ${response.sizeText}`,
  ]
  if (response.finalURL !== "") parts.push(response.finalURL)
  const headers = response.headers.map((header) => `${header.key}: ${header.value}`).join("\n")
  if (headers !== "") parts.push(headers)
  const body = displayText(response, raw)
  if (body !== null && body !== "") parts.push(body)
  return parts.join("\n\n")
}
