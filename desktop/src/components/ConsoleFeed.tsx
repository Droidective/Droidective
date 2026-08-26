import { ChevronRight, CircleAlert, TriangleAlert } from "lucide-react"
import { useEffect, useRef } from "react"

import type { ConsoleRow } from "@/lib/console-feed"
import { tokensFor, type Token } from "@/lib/console-format"

/**
 * The console's rows.
 *
 * Its own file so `JsConsolePane` stays about the bars around it. The feed
 * follows the tail unless the reader has scrolled away from it — the same rule
 * the logcat feed follows, and for the same reason: a console that yanks you
 * back to the bottom while you are reading is unusable on a chatty app.
 */
export function ConsoleFeed({
  rows,
  empty,
  problem,
}: {
  rows: ConsoleRow[]
  empty: boolean
  problem: string | null
}) {
  const scroller = useRef<HTMLDivElement | null>(null)
  const pinned = useRef(true)

  // Follow the tail unless the reader scrolled away from it — the same rule
  // the logcat feed follows.
  useEffect(() => {
    if (pinned.current) scroller.current?.scrollTo({ top: scroller.current.scrollHeight })
  }, [rows])

  return (
    <div
      ref={scroller}
      onScroll={(event) => {
        const element = event.currentTarget
        pinned.current =
          element.scrollHeight - element.scrollTop - element.clientHeight < 24
      }}
      className="min-h-0 flex-1 overflow-auto font-mono text-[11.5px]"
    >
      {empty ? (
        <p className="p-3 font-sans text-text-tertiary">
          {problem ?? "Connected. Anything the app logs shows up here."}
        </p>
      ) : (
        rows.map((row) => <Row key={row.id} row={row} />)
      )}
    </div>
  )
}

function Row({ row }: { row: ConsoleRow }) {
  const tone =
    row.level === "error"
      ? "bg-red-500/10 text-red-300"
      : row.level === "warning"
        ? "bg-amber-500/10 text-amber-200"
        : "text-text-primary"
  return (
    <div className={`flex gap-2 border-b border-border-subtle/40 px-3 py-[3px] ${tone}`}>
      <span className="shrink-0 select-none text-text-tertiary">
        {row.level === "error" ? (
          <CircleAlert size={11} className="mt-[3px]" />
        ) : row.level === "warning" ? (
          <TriangleAlert size={11} className="mt-[3px]" />
        ) : row.local ? (
          <ChevronRight size={11} className="mt-[3px]" />
        ) : (
          <span className="inline-block w-[11px]" />
        )}
      </span>
      <span className="min-w-0 flex-1 whitespace-pre-wrap break-words">
        {row.args.length === 0 ? row.text : <Args row={row} />}
      </span>
      {row.source === null ? null : (
        <span className="shrink-0 select-none text-text-tertiary" title={row.source}>
          {row.source}
        </span>
      )}
    </div>
  )
}

/**
 * A row's arguments, each rendered by Chrome's own rules.
 *
 * Only the *top level* prints bare, which is why the style is per argument and
 * not per row: `console.log('a', {b: 'c'})` is `a {b: 'c'}`.
 */
function Args({ row }: { row: ConsoleRow }) {
  return (
    <>
      {row.args.map((argument, index) => (
        // eslint-disable-next-line react/no-array-index-key -- the arg list is
        // fixed for the life of the row; there is nothing else to key by.
        <span key={index}>
          {index > 0 ? " " : ""}
          {tokensFor(argument, "consoleArgument").map((token, at) => (
            <span key={at} className={colourOf(token)}>
              {token.text}
            </span>
          ))}
        </span>
      ))}
    </>
  )
}

function colourOf(token: Token): string {
  switch (token.kind) {
    case "string":
      return "text-red-300"
    case "number":
    case "boolean":
      return "text-blue-300"
    case "null":
    case "undefined":
      return "text-text-tertiary"
    case "key":
      return "text-purple-300"
    case "className":
      return "text-text-secondary"
    case "function":
      return "text-yellow-200 italic"
    case "punctuation":
      return "text-text-tertiary"
    default:
      return ""
  }
}

