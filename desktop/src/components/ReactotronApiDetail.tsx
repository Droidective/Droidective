import { useState } from "react"
import { Check, Terminal } from "lucide-react"
import { JsonTree } from "@/components/JsonTree"
import { cn } from "@/lib/cn"
import { copyText } from "@/lib/daemon"
import { parseEmbedded } from "@/lib/embedded-json"
import { isJsonObject, type JsonValue } from "@/lib/json"
import { curlCommand } from "@/lib/reactotron-curl"
import { statusTone } from "@/lib/reactotron-filter"

const TABS = [
  { id: "response", label: "Response" },
  { id: "request", label: "Request" },
  { id: "responseHeaders", label: "Resp Headers" },
  { id: "requestHeaders", label: "Req Headers" },
] as const
type Tab = (typeof TABS)[number]["id"]

const STATUS_TONES = {
  ok: "text-rt-ok",
  warn: "text-warn",
  error: "text-danger",
  neutral: "text-rt-number",
}

/**
 * An expanded API row: the whole URL, the three meta lines, Copy as cURL, and
 * the four payload tabs.
 *
 * Each tab gets its own `JsonTree` — keyed by tab, so the opened rows, the raw
 * toggles and the find text belong to the payload on screen. The Mac learned
 * this the hard way: one shared tree meant switching tabs carried the other
 * tab's opened rows, at positional paths that meant something else.
 */
export function ReactotronApiDetail({
  method,
  url,
  status,
  duration,
  request,
  response,
}: {
  method: string
  url: string
  status: number
  duration: number
  request?: JsonValue | undefined
  response?: JsonValue | undefined
}) {
  const [tab, setTab] = useState<Tab>("response")
  const [copied, setCopied] = useState(false)

  return (
    <div className="flex min-w-0 flex-col gap-2">
      {/* The whole URL, wrapped rather than cut: the collapsed row already
          showed the short form, so this is the place the signed query string
          someone came to read actually is. */}
      <p className="font-mono text-[11px] break-all text-rt-key" data-selectable>
        {url}
      </p>

      <div className="flex flex-col gap-0.5">
        <Meta label="Status" value={String(status)} tone={STATUS_TONES[statusTone(status)]} />
        <Meta label="Method" value={method} tone="text-rt-number" />
        <Meta label="Duration" value={`${formatMs(duration)} ms`} tone="text-rt-number" />
      </div>

      <div className="flex items-center">
        <div className="flex flex-1 gap-1 rounded-md bg-bg-root p-0.5">
          {TABS.map((entry) => (
            <button
              key={entry.id}
              type="button"
              onClick={() => {
                setTab(entry.id)
              }}
              aria-pressed={tab === entry.id}
              className={cn(
                "flex-1 rounded-sm px-2 py-0.5 text-[11px]",
                tab === entry.id
                  ? "bg-bg-raised text-text-primary"
                  : "text-text-secondary hover:text-text-primary",
              )}
            >
              {entry.label}
            </button>
          ))}
        </div>
        <button
          type="button"
          onClick={() => {
            void copyText(curlCommand({ method, url, request })).then(() => {
              setCopied(true)
              setTimeout(() => {
                setCopied(false)
              }, 1400)
            })
          }}
          title="Copy a curl command that reproduces this request"
          className={cn(
            "ml-2 flex shrink-0 items-center gap-1.5 rounded-md px-2 py-1 text-[11px]",
            copied ? "bg-accent/20 text-accent" : "bg-bg-raised text-text-secondary hover:text-text-primary",
          )}
        >
          {copied ? <Check size={11} /> : <Terminal size={11} />}
          {copied ? "Copied" : "Copy as cURL"}
        </button>
      </div>

      <JsonTree key={tab} value={payloadFor(tab, request, response)} />
    </div>
  )
}

/**
 * What each tab shows.
 *
 * The response tab prefers the *parsed* body: a JSON body arrives as a string
 * of JSON, and the escaped wall is the one thing nobody can read.
 */
function payloadFor(
  tab: Tab,
  request: JsonValue | undefined,
  response: JsonValue | undefined,
): JsonValue {
  switch (tab) {
    case "response": {
      const body = field(response, "body")
      if (body === undefined) return response ?? null
      return (typeof body === "string" ? parseEmbedded(body) : null) ?? body
    }
    case "request":
      return request ?? null
    case "responseHeaders":
      return field(response, "headers") ?? {}
    case "requestHeaders":
      return field(request, "headers") ?? {}
  }
}

function field(value: JsonValue | undefined, key: string): JsonValue | undefined {
  if (value === undefined || !isJsonObject(value)) return undefined
  return value[key]
}

function Meta({ label, value, tone }: { label: string; value: string; tone: string }) {
  return (
    <div className="flex items-baseline gap-2.5">
      <span className="w-[58px] shrink-0 text-[11px] text-text-tertiary">{label}</span>
      <span className={cn("font-mono text-[11px] font-medium", tone)} data-selectable>
        {value}
      </span>
    </div>
  )
}

/** One decimal place, which is all a millisecond figure earns. */
function formatMs(value: number): string {
  return value >= 100 ? String(Math.round(value)) : value.toFixed(1)
}
