import { useEffect, useRef } from "react"
import { QuickBundlePicker } from "@/components/quick/QuickBundlePicker"
import { QuickForm } from "@/components/quick/QuickForm"
import { QuickFooter, QuickGrid, QuickHeader, QuickList } from "@/components/quick/QuickParts"
import { COLUMNS, useQuickPanel } from "@/hooks/useQuickPanel"

/**
 * The Quick Actions panel — the Mac's `QuickActionsView`.
 *
 * A push-navigation mini app: the root is a grid of everything runnable in
 * place, with the saved commands and the full-app screens listed under it. A
 * form action pushes its fields; a device-scoped action with several devices
 * connected pushes the pick-device interstitial first. Esc pops a screen and
 * closes at the root.
 *
 * Everything it decides is in `useQuickPanel`; this is the arrangement.
 */
export function QuickPanel() {
  const panel = useQuickPanel()
  const atRoot = panel.form === null && panel.picking === null && panel.pickingApp === null

  useKeys({
    onEscape: panel.back,
    onMove: panel.move,
    onEnter: panel.enter,
    // Arrows and Enter belong to the pushed screen's own controls once one is
    // up: a form's Run button is what Enter means there.
    gridKeys: atRoot,
  })

  if (panel.form !== null) {
    return (
      <Screen onBack={panel.back} title={panel.form.title}>
        <QuickForm feature={panel.form} running={panel.running} onRun={panel.submitForm} />
      </Screen>
    )
  }

  if (panel.picking !== null) {
    const feature = panel.picking
    return (
      <Screen onBack={panel.back} title={`Run ${feature.title} on…`}>
        <QuickList
          rows={panel.ready.map((device) => ({ id: device.serial, title: device.label }))}
          onPick={(serial) => {
            panel.pickDevice([serial])
          }}
          {...(feature.supportsRunAll
            ? {
                onPickAll: () => {
                  panel.pickDevice(panel.ready.map((device) => device.serial))
                },
              }
            : {})}
        />
      </Screen>
    )
  }

  if (panel.pickingApp !== null) {
    return (
      <Screen onBack={panel.back} title={`Run ${panel.pickingApp.title} on which app?`}>
        <QuickBundlePicker serial={panel.bundleSerial} onPick={panel.pickApp} />
      </Screen>
    )
  }

  const empty =
    panel.actions.length === 0 && panel.commands.length === 0 && panel.screens.length === 0

  return (
    <div className="flex h-screen flex-col bg-bg-root text-text-primary">
      <QuickHeader
        query={panel.query}
        onQuery={panel.setQuery}
        device={panel.ready[0] ?? null}
        deviceCount={panel.ready.length}
      />
      <div className="min-h-0 flex-1 overflow-y-auto p-3">
        <QuickGrid
          features={panel.actions}
          highlight={panel.highlight}
          armed={panel.armed}
          running={panel.running}
          columns={COLUMNS}
          onActivate={panel.activate}
          onHighlight={panel.setHighlight}
        />
        {panel.commands.length === 0 ? null : (
          <QuickList
            title="Custom Commands"
            rows={panel.commands.map((command) => ({ id: command.id, title: command.name }))}
            onPick={panel.runCommand}
          />
        )}
        {panel.screens.length === 0 ? null : (
          <QuickList
            title="Open in Droidective"
            rows={panel.screens.map((feature) => ({ id: feature.id, title: feature.title }))}
            onPick={(id) => {
              void panel.session.openInApp(id)
            }}
          />
        )}
        {empty ? (
          <p className="px-2 py-8 text-center text-text-tertiary">
            Nothing matches “{panel.query}”.
          </p>
        ) : null}
      </div>
      <QuickFooter outcome={panel.outcome} armed={panel.armed !== null} />
    </div>
  )
}

/** A pushed screen: a way back, a title, and the screen itself. */
function Screen({
  onBack,
  title,
  children,
}: {
  onBack: () => void
  title: string
  children: React.ReactNode
}) {
  return (
    <div className="flex h-screen flex-col bg-bg-root text-text-primary">
      <div className="flex items-center gap-2 border-b border-border-subtle px-3 py-2.5">
        <button
          type="button"
          onClick={onBack}
          aria-label="Back"
          className="rounded px-1.5 text-text-tertiary hover:text-text-primary"
        >
          ‹
        </button>
        <span className="font-medium">{title}</span>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto p-3">{children}</div>
    </div>
  )
}

const ARROWS: Record<string, "up" | "down" | "left" | "right" | undefined> = {
  ArrowUp: "up",
  ArrowDown: "down",
  ArrowLeft: "left",
  ArrowRight: "right",
}

/**
 * The panel's keys.
 *
 * Arrows move the grid **while a query is being typed**, which is the whole
 * point of the panel: two letters and an arrow, without leaving the field. That
 * is why this is a window-level listener rather than the search input's own
 * handler. The handlers go through a ref so re-binding the listener on every
 * keystroke is not what makes that work.
 */
function useKeys({
  onEscape,
  onMove,
  onEnter,
  gridKeys,
}: {
  onEscape: () => void
  onMove: (direction: "up" | "down" | "left" | "right") => void
  onEnter: () => void
  gridKeys: boolean
}) {
  const latest = useRef({ onEscape, onMove, onEnter, gridKeys })
  latest.current = { onEscape, onMove, onEnter, gridKeys }

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const current = latest.current
      if (event.key === "Escape") {
        event.preventDefault()
        current.onEscape()
        return
      }
      if (!current.gridKeys) return
      const direction = ARROWS[event.key]
      if (direction !== undefined) {
        event.preventDefault()
        current.onMove(direction)
        return
      }
      if (event.key === "Enter") {
        event.preventDefault()
        current.onEnter()
      }
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [])
}
