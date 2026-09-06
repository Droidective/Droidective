import { useEffect, useRef, useState } from "react"

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

export function PaletteDemo() {
  const reducedMotion = usePrefersReducedMotion()
  const [query, setQuery] = useState("")
  const [inView, setInView] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const el = ref.current
    if (!el) return
    const observer = new IntersectionObserver(([entry]) => setInView(entry?.isIntersecting ?? false))
    observer.observe(el)
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    if (reducedMotion) {
      setQuery("logcat")
      return
    }
    if (!inView) return
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
  }, [reducedMotion, inView])

  const visible = paletteCommands.filter((c) => matches(query, c.keys, c.name))
  const activeName = visible[0]?.name

  return (
    <div
      ref={ref}
      aria-hidden
      className="overflow-hidden rounded-[18px] border border-white/[0.08] bg-gradient-to-b from-ink-700 to-ink-800 shadow-[0_40px_110px_-30px_rgba(0,0,0,0.8),0_0_0_1px_rgba(105,161,6,0.04),inset_0_1px_0_rgba(231,234,229,0.04)]"
    >
      {/* Title bar */}
      <div className="flex items-center gap-2.5 border-b border-white/[0.06] bg-ink-900/40 px-3.5 py-2.75">
        <span className="flex gap-1.75">
          <i className="size-2.75 rounded-full bg-[#ff5f57]" />
          <i className="size-2.75 rounded-full bg-[#febc2e]" />
          <i className="size-2.75 rounded-full bg-[#28c840]" />
        </span>
        <span className="ml-auto inline-flex items-center gap-1.75 rounded-full border border-white/[0.06] px-2.5 py-1 font-mono text-[11px] text-muted/80">
          <span className="relative flex size-1.5">
            <span className="cta-breathe absolute inline-flex size-full rounded-full bg-green" />
            <span className="relative inline-flex size-1.5 rounded-full bg-green" />
          </span>
          Pixel 8 · Android 14
        </span>
      </div>

      {/* Search row */}
      <div className="relative flex items-center gap-2.75 border-b border-white/[0.06] px-4.5 py-4 after:absolute after:inset-x-0 after:-bottom-px after:h-px after:bg-linear-to-r after:from-transparent after:via-green/50 after:to-transparent">
        <span className="font-mono text-[15px] text-green">&gt;</span>
        <span className="min-h-5 font-mono text-base">{query}</span>
        <span className="-ml-0.5 inline-block h-4.5 w-2 animate-[blink_1.05s_steps(1)_infinite] bg-green shadow-[0_0_8px_rgba(105,161,6,0.3)] motion-reduce:animate-none" />
        <kbd className="ml-auto rounded-md border border-white/[0.08] bg-white/[0.03] px-1.75 py-0.75 text-[11px] text-muted/70">⌘T</kbd>
      </div>

      {/* Results — non-matches dim rather than unmount, so the list height never
          changes. Hiding them collapsed the box and left a large void whenever a
          query matched a single tool, which jumped everything below it. */}
      <ul className="m-0 list-none p-2">
        {paletteCommands.map((cmd) => {
          const shown = matches(query, cmd.keys, cmd.name)
          return (
            <li
              key={cmd.name}
              className={cn(
                "grid grid-cols-[30px_1fr_auto] items-center gap-3.25 rounded-[11px] px-3 py-2.75 transition-all duration-200",
                !shown && "opacity-20",
                shown && cmd.name === activeName && "bg-green/8 shadow-[inset_0_0_0_1px_rgba(105,161,6,0.15)]",
              )}
            >
              <cmd.icon className="size-5.25 text-green" aria-hidden />
              <span className="min-w-0">
                <span className="block text-[14.5px] leading-[1.3] font-semibold">{cmd.name}</span>
                <span className="font-mono text-[11px] text-faint/70">{cmd.category}</span>
              </span>
              <code className="max-w-55 overflow-hidden rounded-[7px] border border-white/[0.06] bg-ink-900/50 px-2.25 py-1 font-mono text-[11.5px] text-ellipsis whitespace-nowrap text-green-dim/80 max-[620px]:hidden">
                {cmd.shell}
              </code>
            </li>
          )
        })}
      </ul>

      {/* Footer */}
      <div className="flex gap-4.5 border-t border-white/[0.06] bg-ink-900/35 px-4 py-2.5 font-mono text-[11px] text-faint/70">
        <span>
          <b className="font-medium text-muted/70">↩</b> run
        </span>
        <span>
          <b className="font-medium text-muted/70">⌘T</b> search
        </span>
        <span>
          <b className="font-medium text-muted/70">esc</b> close
        </span>
        <span className="ml-auto">
          <b className="font-medium text-muted/70 tnum">61</b> tools
        </span>
      </div>
    </div>
  )
}
