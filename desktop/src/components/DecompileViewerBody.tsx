/**
 * One decompiled file's text, with the find query marked.
 *
 * Its own file because `DecompileBrowser` is at oxlint's line ceiling, which
 * is the repo's cue to split.
 */

import { isBinary } from "@/lib/decompile"
import { segments } from "@/lib/console-find"
import type { DecompileFileText } from "@/lib/wire"

export function DecompileViewerBody({
  path,
  source,
  loading,
  find,
}: {
  path: string
  source: DecompileFileText | null
  loading: boolean
  find: string
}) {
  if (loading) return <p className="p-3 text-text-tertiary">Reading…</p>
  if (isBinary(path)) {
    return (
      <p className="p-3 text-text-tertiary">
        This is a binary file — apktool copies assets through as they are.
      </p>
    )
  }
  const text = source?.text ?? ""
  if (find.trim() === "") {
    return (
      <pre className="whitespace-pre p-3 font-mono text-[11.5px] leading-[1.5] text-text-primary">
        {text}
      </pre>
    )
  }
  // The same run-splitting the console's find uses, so a match looks the same
  // wherever this app highlights one.
  return (
    <pre className="whitespace-pre p-3 font-mono text-[11.5px] leading-[1.5] text-text-primary">
      {segments(text, find).map((part, at) =>
        part.match ? (
          // eslint-disable-next-line react/no-array-index-key -- the runs are a
          // pure function of this text and this query.
          <mark key={at} className="bg-yellow-300 text-black">
            {part.text}
          </mark>
        ) : (
          // eslint-disable-next-line react/no-array-index-key -- as above.
          <span key={at}>{part.text}</span>
        ),
      )}
    </pre>
  )
}
