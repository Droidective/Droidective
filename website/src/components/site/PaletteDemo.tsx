import { useEffect, useState } from "react"

import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"
import { paletteCommands, paletteQueries } from "@/lib/content"
import { cn } from "@/lib/utils"

const TYPE_MS = 95
const ERASE_MS = 45
const HOLD_MS = 1500
const REST_MS = 450
const SETTLE_MS = 700

function matches(query: string, keys: string, name: string): boolean {
  const q = query.trim().toLowerCase()
  return q === "" || `${keys} ${name}`.toLowerCase().includes(q)
}

/** The hero's animated ⌘K palette — types real queries and live-filters the list. */
export function PaletteDemo() {
  const reducedMotion = usePrefersReducedMotion()
  const [query, setQuery] = useState("")

  useEffect(() => {
    if (reducedMotion) {
      setQuery("logcat")
      return
    }
    let cancelled = false
    let timer: ReturnType<typeof setTimeout>
    const sleep = (ms: number) =>
      new Promise<void>((resolve) => {
        timer = setTimeout(resolve, ms)
      })

    async function loop() {
      await sleep(SETTLE_MS)
      let i = 0
      while (!cancelled) {
        const word = paletteQueries[i % paletteQueries.length]!
        for (let n = 1; n <= word.length && !cancelled; n++) {
          setQuery(word.slice(0, n))
          await sleep(TYPE_MS)
        }
        await sleep(HOLD_MS)
        for (let n = word.length; n >= 0 && !cancelled; n--) {
          setQuery(word.slice(0, n))
          await sleep(ERASE_MS)
        }
        await sleep(REST_MS)
        i++
      }
    }
    void loop()
    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [reducedMotion])

  const visible = paletteCommands.filter((c) => matches(query, c.keys, c.name))
  const activeName = visible[0]?.name

  return (
    <div
      aria-hidden
      className="overflow-hidden rounded-[18px] border border-border-2 bg-linear-to-b from-ink-700 to-ink-800 shadow-[0_40px_110px_-30px_rgba(0,0,0,0.8),0_0_0_1px_rgba(155,224,33,0.06),inset_0_1px_0_rgba(231,234,229,0.04)]"
    >
      {/* Title bar */}
      <div className="flex items-center gap-2.5 border-b border-border bg-ink-900/40 px-3.5 py-2.75">
        <span className="flex gap-1.75">
          <i className="size-2.75 rounded-full bg-[#ff5f57]" />
          <i className="size-2.75 rounded-full bg-[#febc2e]" />
          <i className="size-2.75 rounded-full bg-[#28c840]" />
        </span>
        <span className="ml-auto inline-flex items-center gap-1.75 rounded-full border border-border px-2.5 py-1 font-mono text-[11.5px] text-muted">
          <span className="size-1.5 rounded-full bg-green shadow-[0_0_7px_var(--color-green)]" />
          Pixel 8 · Android 14
        </span>
      </div>

      {/* Search row */}
      <div className="relative flex items-center gap-2.75 border-b border-border px-4.5 py-4 after:absolute after:inset-x-0 after:-bottom-px after:h-px after:bg-linear-to-r after:from-transparent after:via-green after:to-transparent after:opacity-50">
        <span className="font-mono text-[15px] text-green">&gt;</span>
        <span className="min-h-5 font-mono text-base">{query}</span>
        <span className="-ml-0.5 inline-block h-4.5 w-2 animate-[blink_1.05s_steps(1)_infinite] bg-green shadow-[0_0_8px_rgba(155,224,33,0.3)] motion-reduce:animate-none" />
        <kbd className="ml-auto rounded-md border border-border-2 bg-white/3 px-1.75 py-0.75 text-[11px] text-muted">⌘K</kbd>
      </div>

      {/* Results */}
      <ul className="m-0 max-h-93 list-none overflow-hidden p-2">
        {paletteCommands.map((cmd) => {
          const shown = matches(query, cmd.keys, cmd.name)
          return (
            <li
              key={cmd.name}
              className={cn(
                "grid grid-cols-[30px_1fr_auto] items-center gap-3.25 rounded-[11px] px-3 py-2.75 transition-colors duration-150",
                !shown && "hidden",
                shown && cmd.name === activeName && "bg-green/10 shadow-[inset_0_0_0_1px_rgba(155,224,33,0.22)]",
              )}
            >
              <cmd.icon className="size-5.25 text-green" aria-hidden />
              <span className="min-w-0">
                <span className="block text-[14.5px] leading-[1.3] font-semibold">{cmd.name}</span>
                <span className="font-mono text-[11px] text-faint">{cmd.category}</span>
              </span>
              <code className="max-w-55 overflow-hidden rounded-[7px] border border-border bg-ink-900/50 px-2.25 py-1 font-mono text-[11.5px] text-ellipsis whitespace-nowrap text-green-dim max-[620px]:hidden">
                {cmd.shell}
              </code>
            </li>
          )
        })}
      </ul>

      {/* Footer */}
      <div className="flex gap-4.5 border-t border-border bg-ink-900/35 px-4 py-2.5 font-mono text-[11px] text-faint">
        <span>
          <b className="font-medium text-muted">↩</b> run
        </span>
        <span>
          <b className="font-medium text-muted">⌘K</b> search
        </span>
        <span>
          <b className="font-medium text-muted">esc</b> close
        </span>
        <span className="ml-auto">
          <b className="font-medium text-muted">56</b> tools
        </span>
      </div>
    </div>
  )
}
