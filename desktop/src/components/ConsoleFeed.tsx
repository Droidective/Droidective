import { ChevronRight, CircleAlert, TriangleAlert } from "lucide-react"
import { useEffect, useRef } from "react"

import type { ConsoleSelection } from "@/hooks/useConsoleSelection"
import { cn } from "@/lib/cn"
import { emptyFeedText, type ConsoleRow } from "@/lib/console-feed"
import { segments } from "@/lib/console-find"
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
  connection,
  targetCount,
  find = "",
  currentMatch = null,
  selection = null,
}: {
  rows: ConsoleRow[]
  empty: boolean
  problem: string | null
  connection: string
  targetCount: number
  /** The ⌘F query, highlighted wherever it occurs. */
  find?: string
  /** The match the find bar's arrows are on, scrolled to and marked. */
  currentMatch?: number | null
  /** Row picking, when the host offers it. */
  selection?: ConsoleSelection | null
}) {
  const scroller = useRef<HTMLDivElement | null>(null)
  const pinned = useRef(true)

  // Follow the tail unless the reader scrolled away from it — the same rule
  // the logcat feed follows.
  useEffect(() => {
    if (pinned.current) scroller.current?.scrollTo({ top: scroller.current.scrollHeight })
  }, [rows])

  // Walking to a match wins over following the tail: someone stepping through
  // find has stopped reading the newest line by definition.
  useEffect(() => {
    if (currentMatch === null) return
    scroller.current
      ?.querySelector(`[data-row="${String(currentMatch)}"]`)
      ?.scrollIntoView({ block: "nearest" })
  }, [currentMatch])

  return (
    <div
      ref={scroller}
      onScroll={(event) => {
        const element = event.currentTarget
        pinned.current =
          element.scrollHeight - element.scrollTop - element.clientHeight < 24
      }}
      // Never sideways. A feed that can scroll horizontally lets its content
      // size to max-content, and a long Metro bundle URL then runs off the
      // pane instead of wrapping. Logcat's feed is y-only for the same reason.
      className={cn(
        "min-h-0 flex-1 overflow-y-auto overflow-x-hidden font-mono text-[11.5px]",
        // Only while sweeping: otherwise the browser selects the text under
        // the drag at the same time and two selections fight over one gesture.
        // Off again the moment the button comes up, so copying text out of a
        // row still works.
        selection?.dragging === true && "select-none",
      )}
    >
      {empty ? (
        <p className="p-3 font-sans text-text-tertiary">
          {emptyFeedText(connection, targetCount, problem)}
        </p>
      ) : (
        rows.map((row) => (
          <Row
            key={row.id}
            row={row}
            find={find}
            current={row.id === currentMatch}
            selection={selection}
          />
        ))
      )}
    </div>
  )
}

function Row({
  row,
  find,
  current,
  selection,
}: {
  row: ConsoleRow
  find: string
  current: boolean
  selection: ConsoleSelection | null
}) {
  const tone =
    row.level === "error"
      ? "bg-red-500/10 text-red-300"
      : row.level === "warning"
        ? "bg-amber-500/10 text-amber-200"
        : "text-text-primary"
  // A plain block with inline parts, the way the logcat feed does it — **not** a
  // flex line. As a flex row inside a scrollable feed the message item was
  // sized against max-content and collapsed to one character wide: every log
  // rendered as a vertical column of letters. Found by opening the pane
  // against a real app, not by reading this.
  //
  // `overflow-wrap: anywhere` rather than `break-words`, because the long
  // token here is a Metro bundle URL with no spaces to break at.
  return (
    <div
      data-row={row.id}
      onPointerDown={(event) => {
        selection?.onPointerDown(row.id, event)
      }}
      onPointerEnter={() => {
        selection?.onPointerEnter(row.id)
      }}
      className={cn(
        "whitespace-pre-wrap [overflow-wrap:anywhere] border-b border-border-subtle/40 px-3 py-[3px]",
        tone,
        selection?.has(row.id) === true && "bg-accent/25",
      )}
    >
      {row.source === null ? null : (
        <span
          className="float-right ml-2 select-none text-text-tertiary"
          title={row.source}
        >
          {row.source}
        </span>
      )}
      <Glyph row={row} />
      {row.args.length === 0 ? (
        <Found text={row.text} find={find} current={current} />
      ) : (
        <Args row={row} find={find} current={current} />
      )}
    </div>
  )
}

/** The level's mark, or the width of one so the messages still line up. */
function Glyph({ row }: { row: ConsoleRow }) {
  if (row.level === "error") {
    return <CircleAlert size={11} className="mr-1.5 inline-block align-[-1px] text-red-400" />
  }
  if (row.level === "warning") {
    return <TriangleAlert size={11} className="mr-1.5 inline-block align-[-1px] text-amber-400" />
  }
  if (row.local) {
    return <ChevronRight size={11} className="mr-1.5 inline-block align-[-1px] text-text-tertiary" />
  }
  return <span className="mr-1.5 inline-block w-[11px]" />
}

/**
 * A row's arguments, each rendered by Chrome's own rules.
 *
 * Only the *top level* prints bare, which is why the style is per argument and
 * not per row: `console.log('a', {b: 'c'})` is `a {b: 'c'}`.
 */
function Args({ row, find, current }: { row: ConsoleRow; find: string; current: boolean }) {
  return (
    <>
      {row.args.map((argument, index) => (
        // eslint-disable-next-line react/no-array-index-key -- the arg list is
        // fixed for the life of the row; there is nothing else to key by.
        <span key={index}>
          {index > 0 ? " " : ""}
          {tokensFor(argument, "consoleArgument").map((token, at) => (
            <span key={at} className={colourOf(token)}>
              <Found text={token.text} find={find} current={current} />
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


/**
 * `text`, with every occurrence of the find query marked.
 *
 * Yellow for a match, amber for one in the row the arrows are on — the Mac's
 * two shades, and black text on both so a highlight over a coloured token stays
 * readable.
 */
function Found({ text, find, current }: { text: string; find: string; current: boolean }) {
  if (find.trim() === "") return text
  return (
    <>
      {segments(text, find).map((part, at) =>
        part.match ? (
          // eslint-disable-next-line react/no-array-index-key -- the runs are a
          // pure function of this text and this query; there is no id to use.
          <mark key={at} className={current ? "bg-amber-400 text-black" : "bg-yellow-300 text-black"}>
            {part.text}
          </mark>
        ) : (
          // eslint-disable-next-line react/no-array-index-key -- as above.
          <span key={at}>{part.text}</span>
        ),
      )}
    </>
  )
}
