import { cn } from "@/lib/cn"
import type { CrashReport } from "@/lib/wire"

/**
 * Which colour a kind reads as.
 *
 * The Mac tints Java/RN/ANR/native differently so a list of twenty scans at a
 * glance; the daemon sends no colour (it is a UI decision), so the pairing is
 * made here — the same arrangement `lib/icons.ts` has for glyphs.
 */
const TINTS: Record<string, string> = {
  java: "text-danger bg-danger/12",
  native: "text-danger bg-danger/12",
  reactNative: "text-accent bg-accent/12",
  anr: "text-warn bg-warn/12",
  unknown: "text-text-secondary bg-white/[0.06]",
}

export function KindChip({ crash }: { crash: CrashReport }) {
  return (
    <span
      className={cn(
        "shrink-0 rounded-full px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-[0.04em]",
        TINTS[crash.kind] ?? TINTS["unknown"],
      )}
    >
      {crash.kindLabel}
    </span>
  )
}

/** The crashes, newest first. */
export function CrashList({
  crashes,
  selected,
  onSelect,
}: {
  crashes: CrashReport[]
  selected: string | null
  onSelect: (id: string) => void
}) {
  return (
    <aside className="flex w-[320px] shrink-0 flex-col overflow-y-auto border-r border-border-subtle bg-bg-chrome">
      {crashes.map((crash) => (
        <button
          key={crash.id}
          type="button"
          onClick={() => {
            onSelect(crash.id)
          }}
          className={cn(
            "flex w-full flex-col items-start gap-1 border-b border-border-subtle/50 px-3 py-2 text-left",
            crash.id === selected ? "bg-accent/12" : "hover:bg-white/[0.04]",
          )}
        >
          <span className="flex w-full items-center gap-2">
            <KindChip crash={crash} />
            {crash.timestamp === null ? null : (
              <span className="ml-auto shrink-0 font-mono text-[10.5px] text-text-tertiary">
                {crash.timestamp}
              </span>
            )}
          </span>
          <span className="line-clamp-2 w-full break-all text-[12.5px] text-text-primary">
            {crash.title}
          </span>
          {crash.process === null ? null : (
            <span className="w-full truncate font-mono text-[11px] text-text-secondary">
              {crash.process}
              {crash.pid === null ? "" : ` · ${String(crash.pid)}`}
            </span>
          )}
        </button>
      ))}
    </aside>
  )
}
