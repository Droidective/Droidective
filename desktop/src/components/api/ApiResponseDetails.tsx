import { Copy } from "lucide-react"

import { EmptyNote, IconButton } from "@/components/api/ApiKit"
import { formatBytes } from "@/lib/api/labels"
import { copyText, type ApiSendResponse, type ResponseCookie } from "@/lib/daemon"

/**
 * The response pane's Headers, Cookies and Timing tabs.
 *
 * Split from `ApiResponsePane` for its line budget. Each carries its own copy
 * button, because the thing on screen should always be one click from the
 * clipboard — the Mac's `sectionBar` does the same.
 */
export function ApiResponseDetails({
  tab,
  response,
}: {
  tab: "headers" | "cookies" | "timing"
  response: ApiSendResponse
}) {
  if (tab === "headers") return <Headers response={response} />
  if (tab === "cookies") return <Cookies response={response} />
  return <Timing response={response} />
}

function Headers({ response }: { response: ApiSendResponse }) {
  if (response.headers.length === 0) return <EmptyNote title="No headers." />
  const text = response.headers.map((header) => `${header.key}: ${header.value}`).join("\n")

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <Bar title={`${String(response.headers.length)} headers`} copy={text} />
      <div className="min-h-0 flex-1 overflow-auto px-2 pb-2">
        {response.headers.map((header, index) => (
          <div key={`${header.key}-${String(index)}`} className="flex gap-2 py-0.5">
            <span
              data-selectable
              className="min-w-[170px] shrink-0 font-mono text-[12px] font-bold text-text-primary"
            >
              {header.key}
            </span>
            <span data-selectable className="break-all font-mono text-[12px] text-text-secondary">
              {header.value}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}

function Cookies({ response }: { response: ApiSendResponse }) {
  if (response.cookies.length === 0) return <EmptyNote title="This response set no cookies." />
  const text = response.cookies
    .map((cookie) => {
      const detail = cookieDetail(cookie)
      const line = `${cookie.name}=${cookie.value}`
      return detail === "" ? line : `${line} · ${detail}`
    })
    .join("\n")

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <Bar
        title={response.cookies.length === 1 ? "1 cookie" : `${String(response.cookies.length)} cookies`}
        copy={text}
      />
      <div className="min-h-0 flex-1 overflow-auto px-2 pb-2">
        {response.cookies.map((cookie) => (
          <div key={`${cookie.domain}|${cookie.path}|${cookie.name}`} className="space-y-0.5 py-1">
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="font-mono text-[12px] font-bold text-text-primary">
                {cookie.name}
              </span>
              {cookie.httpOnly ? <Flag>HttpOnly</Flag> : null}
              {cookie.secure ? <Flag>Secure</Flag> : null}
              {cookie.sameSite === "" ? null : <Flag>SameSite={cookie.sameSite}</Flag>}
            </div>
            <p data-selectable className="break-all font-mono text-[11px] text-text-secondary">
              {cookie.value}
            </p>
            <p className="text-[11px] text-text-tertiary">{cookieDetail(cookie)}</p>
          </div>
        ))}
      </div>
    </div>
  )
}

function Timing({ response }: { response: ApiSendResponse }) {
  // A phase the platform did not measure is absent, not zero — off-Darwin
  // there are no URLSession metrics at all, so only Total is ever filled in.
  const timing = response.timing
  const phases: [string, number][] =
    timing === null
      ? [["Total", response.elapsedMs]]
      : (
          [
            ["DNS lookup", timing.dns],
            ["Connect", timing.connect],
            ["TLS handshake", timing.tls],
            ["First byte", timing.firstByte],
            ["Total", timing.total],
          ] as [string, number | null | undefined][]
        ).flatMap(([name, value]) =>
          typeof value === "number" ? [[name, value] as [string, number]] : [],
        )

  const lines = [
    ...phases.map(([name, value]) => `${name}: ${String(Math.round(value))} ms`),
    response.finalURL === "" ? null : `Final URL: ${response.finalURL}`,
    `Sent bytes: ${formatBytes(response.sentBytes)}`,
    ...response.redirects.map((hop) => `${String(hop.statusCode)} ${hop.from} -> ${hop.to}`),
  ].filter((line): line is string => line !== null)

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <Bar title="Timing" copy={lines.join("\n")} />
      <div className="min-h-0 flex-1 space-y-3 overflow-auto p-3">
        <section className="space-y-1">
          {phases.map(([name, value]) => (
            <Row key={name} label={name} value={`${String(Math.round(value))} ms`} />
          ))}
        </section>
        <section className="space-y-1">
          <h3 className="text-[12px] font-medium uppercase tracking-wide text-text-tertiary">
            Request
          </h3>
          <Row label="Final URL" value={response.finalURL} selectable />
          <Row label="Sent bytes" value={formatBytes(response.sentBytes)} />
        </section>
        {response.redirects.length === 0 ? null : (
          <section className="space-y-1">
            <h3 className="text-[12px] font-medium uppercase tracking-wide text-text-tertiary">
              Redirects
            </h3>
            {response.redirects.map((hop, index) => (
              <div key={`${String(hop.statusCode)}-${String(index)}`}>
                <p className="break-all font-mono text-[12px] text-text-primary">
                  {hop.statusCode} → {hop.to}
                </p>
                <p className="break-all text-[11px] text-text-tertiary">from {hop.from}</p>
              </div>
            ))}
          </section>
        )}
      </div>
    </div>
  )
}

function Bar({ title, copy }: { title: string; copy: string }) {
  return (
    <div className="flex items-center gap-2 px-2 py-1">
      <span className="text-[12px] text-text-secondary">{title}</span>
      <IconButton
        label={`Copy ${title}`}
        onClick={() => {
          void copyText(copy)
        }}
      >
        <Copy size={12} />
      </IconButton>
    </div>
  )
}

function Row({
  label,
  value,
  selectable = false,
}: {
  label: string
  value: string
  selectable?: boolean
}) {
  return (
    <div className="flex gap-2">
      <span className="w-[120px] shrink-0 text-[12px] text-text-secondary">{label}</span>
      <span
        {...(selectable ? { "data-selectable": true } : {})}
        className="break-all font-mono text-[12px] text-text-primary"
      >
        {value}
      </span>
    </div>
  )
}

function Flag({ children }: { children: React.ReactNode }) {
  return (
    <span className="rounded-full bg-border-subtle px-1.5 py-px text-[10px] text-text-secondary">
      {children}
    </span>
  )
}

function cookieDetail(cookie: ResponseCookie): string {
  const parts: string[] = []
  if (cookie.domain !== "") parts.push(`domain ${cookie.domain}`)
  if (cookie.path !== "") parts.push(`path ${cookie.path}`)
  if (cookie.maxAge !== "") parts.push(`max-age ${cookie.maxAge}`)
  if (cookie.expires !== "") parts.push(`expires ${cookie.expires}`)
  return parts.join(" · ")
}
