import { JsonTree } from "@/components/JsonTree"
import { ReactotronApiDetail } from "@/components/ReactotronApiDetail"
import { looksLikeJson } from "@/lib/embedded-json"
import { isJsonObject, type JsonValue } from "@/lib/json"
import type { ReactotronEvent, StackFrame } from "@/lib/reactotron"

/** Longest raw text a non-JSON payload shows before it is cut. */
const MAX_TEXT = 20_000

/**
 * What an expanded row shows, per event kind.
 *
 * Most kinds are their payload as a tree, which is why this is short: the tree
 * is the general answer, and only the kinds with something else worth saying —
 * an API call's URL and timings, a log's stack, a duration — get their own
 * shape. Same split as the Mac's type-specific bodies.
 */
export function ReactotronDetail({ event, payload }: { event: ReactotronEvent; payload?: JsonValue | undefined }) {
  switch (event.kind) {
    case "apiResponse":
      return (
        <ReactotronApiDetail
          method={event.method}
          url={event.url}
          status={event.status}
          duration={event.duration}
          request={event.request}
          response={event.response}
        />
      )
    case "log":
      return <LogDetail stack={event.stack} payload={payload} />
    case "stateAction":
      return (
        <Sectioned ms={event.ms}>
          <JsonTree value={event.action ?? payload ?? {}} />
        </Sectioned>
      )
    case "benchmark":
      return <BenchmarkDetail steps={event.steps} />
    default:
      return payload === undefined ? <Nothing /> : <JsonTree value={payload} />
  }
}

/**
 * A log's message, then its stack.
 *
 * A logged object gets the tree. So does a message that is *itself* a string of
 * JSON — `JSON.stringify` before `console.log` is common, and it produces the
 * same escaped wall a stringified request body does.
 */
function LogDetail({ stack, payload }: { stack: StackFrame[]; payload: JsonValue | undefined }) {
  const message = payload !== undefined && isJsonObject(payload) ? payload["message"] : undefined
  return (
    <div className="flex min-w-0 flex-col gap-2">
      {message === undefined ? null : <Message value={message} />}
      {stack.length === 0 ? null : <Stack stack={stack} />}
      {message === undefined && stack.length === 0 ? (
        payload === undefined ? <Nothing /> : <JsonTree value={payload} />
      ) : null}
    </div>
  )
}

function Message({ value }: { value: JsonValue }) {
  const structured =
    Array.isArray(value) || isJsonObject(value) || (typeof value === "string" && looksLikeJson(value))
  if (structured) return <JsonTree value={value} />
  return (
    <p className="font-mono text-[11.5px] whitespace-pre-wrap break-words text-text-primary" data-selectable>
      {typeof value === "string" ? value.slice(0, MAX_TEXT) : String(value)}
    </p>
  )
}

/**
 * The frames the client sent.
 *
 * Shown as they arrived rather than symbolicated: turning bundle coordinates
 * back into the developer's own file needs Metro's `/symbolicate`, which is the
 * JS Console's `MetroSymbolicator` on the Mac and is its own change here.
 */
function Stack({ stack }: { stack: StackFrame[] }) {
  return (
    <div className="flex flex-col gap-px">
      {stack.slice(0, 40).map((frame, index) => (
        <p
          key={`${frame.fileName}:${frame.lineNumber ?? 0}:${index}`}
          className="font-mono text-[10.5px] text-text-tertiary"
          data-selectable
        >
          <span className="text-rt-name">{frame.functionName === "" ? "(anonymous)" : frame.functionName}</span>
          {" — "}
          {frame.fileName}
          {frame.lineNumber === null ? "" : `:${frame.lineNumber}`}
          {frame.columnNumber === null ? "" : `:${frame.columnNumber}`}
        </p>
      ))}
    </div>
  )
}

function BenchmarkDetail({ steps }: { steps: { title: string; time: number; delta: number }[] }) {
  return (
    <div className="flex flex-col gap-px">
      {steps.map((step, index) => (
        <div key={`${step.title}:${index}`} className="flex items-baseline gap-2.5">
          <span className="min-w-0 flex-1 truncate text-[11.5px] text-text-primary">{step.title}</span>
          <span className="shrink-0 font-mono text-[11px] text-rt-number tabular-nums">
            +{step.delta.toFixed(1)} ms
          </span>
          <span className="w-[70px] shrink-0 text-right font-mono text-[11px] text-text-tertiary tabular-nums">
            {step.time.toFixed(1)} ms
          </span>
        </div>
      ))}
    </div>
  )
}

function Sectioned({ ms, children }: { ms?: number | undefined; children: React.ReactNode }) {
  return (
    <div className="flex min-w-0 flex-col gap-1.5">
      {ms === undefined ? null : (
        <div className="flex items-baseline gap-2.5">
          <span className="w-[58px] shrink-0 text-[11px] text-text-tertiary">duration</span>
          <span className="font-mono text-[11px] text-rt-number">{ms.toFixed(1)} ms</span>
        </div>
      )}
      {children}
    </div>
  )
}

function Nothing() {
  return <p className="text-[11px] text-text-tertiary">This event carried no payload.</p>
}
