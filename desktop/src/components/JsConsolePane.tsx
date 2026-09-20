import { useEffect, useMemo, useState } from "react"

import { Bar, ConsoleFeed, Filters, JsConsoleFindBar, Prompt } from "@/components/js-console"
import { useJsConsole, DEFAULT_METRO_PORT } from "@/hooks/useJsConsole"
import { useConsoleExport } from "@/hooks/useConsoleExport"
import { useConsoleFind } from "@/hooks/useConsoleFind"
import { useJsConsoleActions } from "@/hooks/useJsConsoleActions"
import { useNotifications } from "@/hooks/useNotifications"
import { filtered, levelCounts, type Level } from "@/lib/console-feed"
import type { Device } from "@/lib/wire"

/**
 * JS Console — the Mac's `JSConsoleView`.
 *
 * A Hermes Chrome-DevTools-Protocol console for React Native: Metro's target
 * list, a live feed, and a prompt. The device needs `adb reverse` to reach
 * Metro, which is the one thing here that goes through the daemon.
 *
 * The socket itself is the webview's — see `useJsConsole` for why.
 */
export function JsConsolePane({ device, active }: { device: Device | null; active: boolean }) {
  const [port, setPort] = useState(DEFAULT_METRO_PORT)
  const console = useJsConsole(port)
  const { show } = useNotifications()
  const [hidden, setHidden] = useState<ReadonlySet<Level>>(new Set())
  const [query, setQuery] = useState("")
  const [draft, setDraft] = useState("")

  const { refresh } = console
  useEffect(() => {
    refresh()
  }, [refresh])

  const shown = useMemo(
    () => filtered(console.rows, { hidden, query }),
    [console.rows, hidden, query],
  )
  const counts = useMemo(() => levelCounts(console.rows), [console.rows])
  const exporting = useConsoleExport(shown)
  const find = useConsoleFind(shown, active)

  const actions = useJsConsoleActions({
    device,
    port,
    reloadJs: console.reloadJs,
    refresh,
  })

  return (
    <div className="flex h-full min-h-0 flex-col">
      <Bar
        console={console}
        port={port}
        onPort={setPort}
        serial={device?.serial ?? null}
        onReload={actions.reload}
        onReport={show}
        onReverse={device === null ? null : actions.reverse}
      />
      <Filters
        hidden={hidden}
        counts={counts}
        query={query}
        onQuery={setQuery}
        onHidden={setHidden}
        onClear={console.clear}
        exporting={exporting}
        onFind={find.openBar}
      />
      {find.open ? (
        <JsConsoleFindBar
          query={find.query}
          onQuery={find.setQuery}
          count={find.count}
          hasMatches={find.hasMatches}
          onNext={find.next}
          onPrev={find.prev}
          onClose={find.close}
        />
      ) : null}
      <ConsoleFeed
        rows={shown}
        empty={console.rows.length === 0}
        problem={console.problem}
        connection={console.connection}
        targetCount={console.targets.length}
        find={find.open ? find.query : ""}
        currentMatch={find.current}
      />
      <Prompt
        value={draft}
        enabled={console.connection === "connected"}
        onChange={setDraft}
        onSubmit={() => {
          console.evaluate(draft)
          setDraft("")
        }}
      />
    </div>
  )
}
