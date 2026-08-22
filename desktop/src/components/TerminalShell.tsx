import { FitAddon } from "@xterm/addon-fit"
import { Terminal } from "@xterm/xterm"
import { useEffect, useRef, useState } from "react"
// Vite takes xterm's stylesheet through the bundler as a side effect.
// oxlint-disable-next-line import/no-unassigned-import
import "@xterm/xterm/css/xterm.css"
import { openTerminal, type TerminalSession } from "@/lib/daemon"
import { decodeChunk, encodeBinary, encodeInput } from "@/lib/terminal"
import type { PtyChunk, StreamUpdate } from "@/lib/wire"

export interface TerminalShellProps {
  /**
   * The device to export as `ANDROID_SERIAL`, captured when this pane was
   * created. Constant for the pane's life on purpose: the Mac scopes a terminal
   * to the device selected *at open*, and re-keying on the device bar would
   * restart someone's shell out from under them.
   */
  serial: string | null
  /** Whether this pane is the visible, focused one. */
  active: boolean
  /** The shell exited, or never started. The pane closes itself. */
  onExit: (reason: string) => void
}

/**
 * One shell, drawn by xterm.js over a `pty` subscription.
 *
 * The interesting half is what it does *not* do: it never decodes the output.
 * Chunks arrive as bytes because a pty read ends wherever its buffer filled, so
 * xterm's own decoder is what carries a half-written character into the next
 * write — see `decodeChunk`.
 */
export function TerminalShell({ serial, active, onExit }: TerminalShellProps) {
  const host = useRef<HTMLDivElement>(null)
  const fit = useRef<FitAddon | null>(null)
  const terminal = useRef<Terminal | null>(null)
  const [failure, setFailure] = useState<string | null>(null)

  // `onExit` is read through a ref so the effect below can depend on nothing
  // but `serial`.
  //
  // This is load-bearing, not tidiness. The caller builds `onExit` inline —
  // `() => closePane(tab, pane)` — so it is a new function on every render, and
  // an effect that depended on it would tear the shell down and open a new one
  // on any re-render of the pane: a new pty, a fresh prompt, and whatever was
  // running gone. The invariant to preserve is that the dependency list holds
  // only value types, so no reference identity can churn it.
  const exit = useRef(onExit)
  useEffect(() => {
    exit.current = onExit
  }, [onExit])

  useEffect(() => {
    const element = host.current
    if (!element) return

    const { term, fitAddon } = createTerminal(element)
    terminal.current = term
    fit.current = fitAddon

    // A shell can outlive the effect that opened it: React runs an effect
    // twice in development, and the second pass must not leave the first
    // pty running with nothing reading it.
    let session: TerminalSession | null = null
    let abandoned = false

    openTerminal(
      { serial, columns: term.cols, rows: term.rows },
      updateHandler(term, (reason) => exit.current(reason), setFailure),
    ).then(
      (opened) => {
        if (abandoned) {
          void opened.stop()
          return
        }
        session = opened
        term.onData((data) => {
          void opened.send(encodeInput(data)).catch(ignore)
        })
        // Mouse reports and the like: already bytes, and encoding them as text
        // would double every coordinate above 127.
        term.onBinary((data) => {
          void opened.send(encodeBinary(data)).catch(ignore)
        })
      },
      (error: unknown) => {
        setFailure(error instanceof Error ? error.message : String(error))
      },
    )

    // The shell has to be told the window changed or it keeps drawing to the
    // old width. `fit` decides the cell count; the daemon's ioctl is what makes
    // the program inside re-wrap.
    const observer = new ResizeObserver(() => {
      if (element.clientWidth === 0 || element.clientHeight === 0) return
      fitAddon.fit()
      void session?.resize(term.cols, term.rows).catch(ignore)
    })
    observer.observe(element)

    return () => {
      abandoned = true
      observer.disconnect()
      void session?.stop().catch(ignore)
      term.dispose()
      terminal.current = null
      fit.current = null
    }
  }, [serial])

  useRefitWhenShown({ active, host, fit, terminal })

  return (
    <div className="relative flex min-h-0 min-w-0 flex-1 flex-col bg-bg-root">
      <div ref={host} className="min-h-0 min-w-0 flex-1 p-1" />
      {failure === null ? null : (
        <p className="border-t border-border-subtle bg-bg-surface px-3 py-2 text-text-secondary">
          {failure}
        </p>
      )}
    </div>
  )
}

/**
 * Re-fits and focuses a terminal when its tab comes to the front.
 *
 * A hidden tab is `display: none`, which measures as zero — so without this a
 * terminal keeps whatever size it had when its tab was last in front, and the
 * program inside draws to the wrong width.
 */
function useRefitWhenShown(args: {
  active: boolean
  host: React.RefObject<HTMLDivElement | null>
  fit: React.RefObject<FitAddon | null>
  terminal: React.RefObject<Terminal | null>
}) {
  const { active, host, fit, terminal } = args
  useEffect(() => {
    if (!active) return
    const frame = requestAnimationFrame(() => {
      const element = host.current
      if (!element || element.clientWidth === 0) return
      fit.current?.fit()
      terminal.current?.focus()
    })
    return () => {
      cancelAnimationFrame(frame)
    }
  }, [active, host, fit, terminal])
}

/** An xterm sized to `element`, with the addon that keeps it sized. */
function createTerminal(element: HTMLDivElement) {
  const term = new Terminal({
    allowProposedApi: true,
    cursorBlink: true,
    fontFamily: "'SF Mono', 'Cascadia Mono', 'DejaVu Sans Mono', Menlo, monospace",
    fontSize: 12,
    // The shell writes far more than a screen; this is the scrollback the
    // Mac's terminal keeps.
    scrollback: 10_000,
    theme: terminalTheme(),
  })
  const fitAddon = new FitAddon()
  term.loadAddon(fitAddon)
  term.open(element)
  fitAddon.fit()
  return { term, fitAddon }
}

/**
 * What arrives on the subscription.
 *
 * A module-level function rather than an inline closure so the effect above
 * stays readable — and so the one branch worth arguing about is visible: a
 * `dropped` gap in a byte stream can be half an escape sequence, which makes
 * everything after it draw wrong. Saying so beats a terminal that has quietly
 * become gibberish.
 */
function updateHandler(
  term: Terminal,
  onExit: (reason: string) => void,
  onFailure: (message: string) => void,
) {
  return (update: StreamUpdate<PtyChunk>) => {
    switch (update.event) {
      case "batch":
        for (const chunk of update.items) term.write(decodeChunk(chunk.data))
        break
      case "ended":
        onExit(update.reason)
        break
      case "failed":
        onFailure(update.message)
        break
      case "dropped":
        term.write("\r\n\u001B[33m[output dropped \u2014 the terminal is behind]\u001B[0m\r\n")
        break
      default:
        break
    }
  }
}

/**
 * xterm needs concrete colours, so they are read from the app's own tokens
 * rather than restated — a palette copied here would drift the first time
 * `index.css` changed.
 */
function terminalTheme() {
  const style = getComputedStyle(document.documentElement)
  const token = (name: string, fallback: string) => {
    const value = style.getPropertyValue(name).trim()
    return value.length > 0 ? value : fallback
  }
  return {
    background: token("--color-bg-root", "#1a1a1a"),
    foreground: token("--color-text-primary", "#ececec"),
    cursor: token("--color-accent", "#6ecc1f"),
    cursorAccent: token("--color-bg-root", "#1a1a1a"),
    selectionBackground: "#ffffff30",
  }
}

/** A send that lost its race with teardown is not worth a console entry. */
function ignore() {}
