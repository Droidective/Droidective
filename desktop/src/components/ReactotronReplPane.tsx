import { useState } from "react"
import { RefreshCw, Terminal } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { StateCard } from "@/components/ReactotronStateCard"
import type { ReactotronReplSession } from "@/hooks/useReactotronRepl"

/**
 * Reactotron's REPL — the Mac's `replPane`.
 *
 * Evaluate an expression against the running app, against the values it
 * registered with `Reactotron.repl(name, value)`. The names are listed above
 * the box because nothing else says what is in scope, and an expression
 * referring to something that is not there simply comes back undefined.
 */
export function ReactotronReplPane({ session }: { session: ReactotronReplSession }) {
  const [code, setCode] = useState("")
  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      <div className="flex flex-col gap-3 p-3.5">
        {session.notice === null ? null : <Banner tone="warn">{session.notice}</Banner>}

        <StateCard
          icon={Terminal}
          title="REPL"
          subtitle="Evaluate JS against values your app registered with Reactotron.repl(name, value)."
          actions={
            <button
              type="button"
              title="Refresh available values"
              aria-label="Refresh available values"
              onClick={session.refresh}
              className="shrink-0 text-text-tertiary hover:text-text-primary"
            >
              <RefreshCw size={13} />
            </button>
          }
        >
          {session.names.length === 0 ? null : (
            <p className="font-mono text-[11px] text-text-tertiary">
              Available: {session.names.join(", ")}
            </p>
          )}

          <textarea
            value={code}
            aria-label="Expression"
            placeholder="e.g. store.getState()"
            rows={2}
            onChange={(event) => {
              setCode(event.target.value)
            }}
            className="w-full resize-y rounded-md border border-border-subtle bg-bg-raised px-2.5 py-1.5 font-mono text-[12px] text-text-primary outline-none focus:border-accent placeholder:text-text-tertiary"
          />
          <div className="flex justify-end">
            <Button
              tone="primary"
              disabled={code.trim() === ""}
              onClick={() => {
                session.run(code)
              }}
            >
              Evaluate
            </Button>
          </div>

          {session.result === null ? null : (
            <>
              <h4 className="text-[12px] font-semibold text-text-primary">Result</h4>
              <pre className="overflow-x-auto whitespace-pre-wrap rounded-md bg-bg-raised p-2 font-mono text-[11px] text-text-secondary">
                {session.result}
              </pre>
            </>
          )}
        </StateCard>
      </div>
    </div>
  )
}
