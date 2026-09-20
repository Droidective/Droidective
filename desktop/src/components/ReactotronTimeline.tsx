import { useMemo, useState } from "react"

import {
  AppRestartMenu,
  ReactotronFeed,
  ReactotronFilterSheet,
  ReactotronNotices,
  ReactotronStatus,
  ReactotronToolbar,
  ReactotronSplitBar,
  RENDER_WINDOW,
  ReverseButton,
  RowSelectionMenu,
} from "@/components/reactotron"
import type { useReactotron } from "@/hooks/useReactotron"
import type { useReactotronActions } from "@/hooks/useReactotronActions"
import { useReactotronSelection, type ReactotronSelection } from "@/hooks/useReactotronSelection"
import { copyText } from "@/lib/daemon"
import { seenMethods } from "@/lib/reactotron-filter"
import type { TimelineRow } from "@/lib/reactotron-rows"
import {
  clearPane,
  clearedEmpty,
  emptyPanes,
  toggleSplit,
  visibleIn,
  withPane,
  type PaneState,
  type PanesState,
} from "@/lib/reactotron-panes"
import type { Device } from "@/lib/wire"

export interface TimelineProps {
  feed: ReturnType<typeof useReactotron>
  actions: ReturnType<typeof useReactotronActions>
  device: Device | null
}

/**
 * The timeline, in one pane or two.
 *
 * Split gives each pane its own filter and order over **one shared buffer** —
 * API traffic on one side, logs on the other, which is what the Mac's
 * onboarding sheet sells it as. The model is `lib/reactotron-panes.ts`; what is
 * here is the layout and where the global controls live.
 *
 * Single-pane keeps the shape it had: the global controls ride the pane's own
 * toolbar, so the timeline is not topped by two stacked strips. The dedicated
 * strip appears only in split mode, where the pane toolbars are per-pane and
 * the globals need a home of their own — the Mac's arrangement exactly.
 */
export function ReactotronTimeline({ feed, actions, device }: TimelineProps) {
  const [panes, setPanes] = useState<PanesState>(emptyPanes)
  const { timeline } = feed

  const globals = (
    <>
      <AppRestartMenu
        serial={device?.serial ?? null}
        subject={{ kind: "client", name: timeline.clients[0]?.name ?? null }}
        onReport={actions.report}
      />
      {/* Beside Restart, as on the Mac. It used to appear only where the status
          bar offers it — while no client is connected — so a tunnel that
          dropped with the client still listed left no way to re-open it, which
          is the one moment you need the button. */}
      <ReverseButton disabled={device === null} onReverse={actions.openTunnel} />
    </>
  )

  const status = (
    <>
      <ReactotronStatus
        relay={feed.relay}
        clients={timeline.clients.map((client) => client.name)}
        port={timeline.port}
        rows={timeline.rows.length}
        shown={visibleIn(timeline.rows, panes.panes[0]).length}
        rendered={Math.min(visibleIn(timeline.rows, panes.panes[0]).length, RENDER_WINDOW)}
        renderWindow={RENDER_WINDOW}
        hasDevice={device !== null}
        onReverse={actions.openTunnel}
      />
      <ReactotronNotices
        error={feed.error?.message ?? null}
        ended={feed.ended}
        failure={actions.failure}
        notice={actions.notice}
        tunnel={actions.tunnel}
      />
    </>
  )

  const pane = (index: number) => (
    <TimelinePane
      key={index}
      state={panes.panes[index === 0 ? 0 : 1]}
      onState={(next) => {
        setPanes((current) => withPane(current, index, next))
      }}
      onClearPane={() => {
        setPanes((current) => clearPane(current, index, timeline.rows))
      }}
      rows={timeline.rows}
      total={timeline.rows.length}
      actions={actions}
      split={panes.split}
      onSplit={
        panes.split
          ? null
          : () => {
              setPanes(toggleSplit)
            }
      }
      trailing={panes.split ? null : globals}
    />
  )

  if (!panes.split) {
    return (
      <>
        {pane(0)}
        {status}
      </>
    )
  }
  return (
    <>
      <ReactotronSplitBar
        events={timeline.rows.length}
        onToggleSplit={() => {
          setPanes(toggleSplit)
        }}
        onClearAll={feed.clear}
        trailing={globals}
      />
      {status}
      <div className="flex min-h-0 flex-1">
        <div className="flex min-w-0 flex-1 flex-col">{pane(0)}</div>
        <div className="w-px shrink-0 bg-border-subtle" />
        <div className="flex min-w-0 flex-1 flex-col">{pane(1)}</div>
      </div>
    </>
  )
}

/** One pane: its toolbar, its feed, its filter sheet, its own selection. */
function TimelinePane({
  state,
  onState,
  onClearPane,
  rows,
  total,
  actions,
  split,
  onSplit,
  trailing,
}: {
  state: PaneState
  onState: (next: PaneState) => void
  onClearPane: () => void
  rows: readonly TimelineRow[]
  total: number
  actions: ReturnType<typeof useReactotronActions>
  split: boolean
  /** Opens the split — only offered by the single pane, as on the Mac. */
  onSplit: (() => void) | null
  trailing: React.ReactNode
}) {
  const [filtering, setFiltering] = useState(false)
  const visible = useMemo(() => visibleIn(rows, state), [rows, state])
  const methods = useMemo(() => seenMethods(rows, state.filter.method), [rows, state.filter.method])
  const selection = useReactotronSelection(visible, reportingCopy(actions.report))

  return (
    <>
      <ReactotronToolbar
        filter={state.filter}
        onFilter={(filter) => {
          onState({ ...state, filter })
        }}
        visible={visible.length}
        total={total}
        newestFirst={state.newestFirst}
        onNewestFirst={(newestFirst) => {
          onState({ ...state, newestFirst })
        }}
        onOpenFilters={() => {
          setFiltering(true)
        }}
        onClear={onClearPane}
        onExport={actions.exportShown}
        onCopyAll={actions.copyShown}
        onSplit={onSplit}
        trailing={
          <>
            {trailing}
            <TimelineSelectionMenu selection={selection} />
          </>
        }
      />
      <ReactotronFeed
        rows={visible}
        newestFirst={state.newestFirst}
        total={total}
        selection={selection}
        clearedEmpty={clearedEmpty(state, visible)}
        rightPane={split && onSplit === null && trailing === null}
      />
      {filtering ? (
        <ReactotronFilterSheet
          filter={state.filter}
          seenMethods={methods}
          onApply={(applied) => {
            onState({ ...state, filter: applied })
            setFiltering(false)
          }}
          onDismiss={() => {
            setFiltering(false)
          }}
        />
      ) : null}
    </>
  )
}

/** The picked-rows control, which the Mac shows only while something is picked. */
function TimelineSelectionMenu({ selection }: { selection: ReactotronSelection }) {
  if (selection.count === 0) return null
  return (
    <RowSelectionMenu
      count={selection.count}
      noun="events"
      onCopy={selection.copy}
      onCopyAsJson={selection.copyAsJson}
      onDeselect={selection.clear}
    />
  )
}

/**
 * What a selection copy does once the text is built: put it on the clipboard
 * and say how many went, through whichever slot the pane reports into.
 */
function reportingCopy(report: (outcome: { ok: boolean; message: string }) => void) {
  return (text: string, count: number, asJson: boolean) => {
    void copyText(text).then(() => {
      report({
        ok: true,
        message: `Copied ${String(count)} ${asJson ? "events as JSON" : "events"}`,
      })
    })
  }
}
