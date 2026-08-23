import { useRef, useState } from "react"
import { ChevronDown, RotateCw, Trash2 } from "lucide-react"
import { ConfirmDialog } from "@/components/ConfirmDialog"
import { useDismissOnOutside } from "@/hooks/useDismissOnOutside"
import { useAppRestart } from "@/hooks/useAppRestart"
import { cn } from "@/lib/cn"
import { askMessage, CLEAR_DATA_PROMPT, type ClearScope } from "@/lib/reactotron-restart"

/**
 * The Mac's split Restart button: pressing it restarts, and the chevron opens
 * the two clearing variants.
 *
 * A split button rather than three separate ones because the plain restart is
 * what someone wants nine times out of ten, and burying it among the
 * destructive variants makes the common case the hardest to reach. Clearing
 * data always goes through a confirmation — it signs you out and wipes local
 * storage — and clearing cache never does.
 */
export function ReactotronRestartMenu({
  serial,
  clientName,
  onReport,
}: {
  serial: string | null
  /** What the connected client called itself, or null when none is connected. */
  clientName: string | null
  /** Where the outcome goes — a banner, a toast, whatever the caller has. */
  onReport: (outcome: { ok: boolean; message: string }) => void
}) {
  const restart = useAppRestart()
  const [open, setOpen] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const menu = useRef<HTMLDivElement | null>(null)

  useDismissOnOutside(menu, setOpen)

  const run = (scope: ClearScope) => {
    setOpen(false)
    if (serial === null) return
    void restart.restart({ serial, clientName, scope }).then((outcome) => {
      // `ask` means the target could not be established. The Mac opens a picker
      // sheet; there is none here yet, so the reason names the way out instead
      // of being swallowed — see backlog 24's remaining line.
      onReport({
        ok: outcome.ok,
        message:
          outcome.ask === undefined ? outcome.message : askMessage(outcome.ask, clientName),
      })
    })
  }

  const disabled = serial === null || restart.busy
  return (
    <div ref={menu} className="relative flex shrink-0">
      <SplitButton
        busy={restart.busy}
        disabled={disabled}
        expanded={open}
        onPrimary={() => {
          run(null)
        }}
        onToggle={() => {
          setOpen(!open)
        }}
      />
      {open ? (
        <div
          role="menu"
          className="absolute top-full right-0 z-40 mt-1 min-w-[210px] rounded-md border border-border-subtle bg-bg-raised py-1 shadow-2xl"
        >
          <Item
            icon={<RotateCw size={11} />}
            label="Clear cache and restart"
            onClick={() => {
              run("cache")
            }}
          />
          <Item
            icon={<Trash2 size={11} />}
            label="Clear data and restart"
            destructive
            onClick={() => {
              setOpen(false)
              setConfirming(true)
            }}
          />
        </div>
      ) : null}

      {confirming ? (
        <ConfirmDialog
          title="Clear data and restart?"
          message={CLEAR_DATA_PROMPT}
          confirmLabel="Clear Data & Restart"
          onConfirm={() => {
            setConfirming(false)
            run("data")
          }}
          onCancel={() => {
            setConfirming(false)
          }}
        />
      ) : null}
    </div>
  )
}

/**
 * Restart on the left, the variants behind the chevron on the right.
 *
 * The plain restart is what someone wants nine times out of ten, so it stays a
 * single press rather than an item in a list of destructive options.
 */
function SplitButton({
  busy,
  disabled,
  expanded,
  onPrimary,
  onToggle,
}: {
  busy: boolean
  disabled: boolean
  expanded: boolean
  onPrimary: () => void
  onToggle: () => void
}) {
  return (
    <>
      <button
        type="button"
        disabled={disabled}
        onClick={onPrimary}
        title="Stop the app and start it again"
        className="flex items-center gap-1.5 rounded-l-md bg-bg-raised px-2 py-1 text-[11.5px] text-text-secondary enabled:hover:text-text-primary disabled:opacity-40"
      >
        <RotateCw size={11} />
        {busy ? "Restarting…" : "Restart app"}
      </button>
      <button
        type="button"
        disabled={disabled}
        onClick={onToggle}
        aria-label="Restart options"
        aria-expanded={expanded}
        className="flex items-center rounded-r-md border-l border-bg-root bg-bg-raised px-1 text-text-secondary enabled:hover:text-text-primary disabled:opacity-40"
      >
        <ChevronDown size={11} />
      </button>
    </>
  )
}

function Item({
  icon,
  label,
  destructive = false,
  onClick,
}: {
  icon: React.ReactNode
  label: string
  destructive?: boolean
  onClick: () => void
}) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={onClick}
      className={cn(
        "flex w-full items-center gap-2 px-3 py-1 text-left text-[12.5px] hover:bg-accent/20",
        destructive ? "text-danger" : "text-text-primary",
      )}
    >
      {icon}
      {label}
    </button>
  )
}
