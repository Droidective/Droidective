import { useCallback, useEffect, useState } from "react"
import { Circle, CheckCircle2, RefreshCw, ShieldAlert, ShieldCheck, ShieldQuestion } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { NoDevice } from "@/components/NoDevice"
import { asDaemonError, rootStatus } from "@/lib/daemon"
import { cn } from "@/lib/cn"
import type { DaemonError, Device, RootStatusResponse } from "@/lib/wire"

/**
 * The root probe — a verdict header over the individual signals behind it.
 *
 * The Mac's `RootStatusView`, laid out the same way: a large tinted shield, the
 * summary in title weight, one line saying what the verdict means for you, and
 * a Re-check button on the trailing edge. A working `su` shell is the
 * definitive proof; the weaker signals (su binary, Magisk, build tags, SELinux)
 * are listed for context rather than folded into the verdict, which is why
 * every one of them travels over the wire.
 */
export function RootStatusPane({ device }: { device: Device | null }) {
  const [status, setStatus] = useState<RootStatusResponse | null>(null)
  const [error, setError] = useState<DaemonError | null>(null)

  const serial = device?.serial ?? null
  const load = useCallback(async () => {
    if (serial === null) return
    // Cleared first, so a re-check shows the probe running rather than the
    // previous device's verdict — the Mac nils its state for the same reason.
    setStatus(null)
    setError(null)
    try {
      setStatus(await rootStatus(serial))
    } catch (thrown) {
      setError(asDaemonError(thrown))
    }
  }, [serial])

  useEffect(() => {
    void load()
  }, [load])

  if (!device) return <NoDevice feature="root-status" title="Root Status" />

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <div className="mx-auto flex w-full max-w-[560px] flex-col gap-4 p-4">
        {error === null ? null : <Banner tone="error">{error.message}</Banner>}
        {status === null ? (
          error === null ? (
            <p className="p-6 text-center text-text-tertiary">Probing root…</p>
          ) : null
        ) : (
          <>
            <Header status={status} onRecheck={load} />
            <div className="overflow-hidden rounded-lg bg-bg-surface">
              {status.signals.map((signal, index) => (
                <div
                  key={signal.name}
                  className={cn(
                    "flex items-start gap-2.5 px-3 py-2",
                    index > 0 && "border-t border-border-subtle",
                  )}
                >
                  {signal.indicatesRoot ? (
                    <CheckCircle2 size={14} className="mt-0.5 shrink-0 text-accent" />
                  ) : (
                    <Circle size={14} className="mt-0.5 shrink-0 text-text-tertiary" />
                  )}
                  <div className="min-w-0">
                    <p className="text-text-primary">{signal.name}</p>
                    <p className="text-[11.5px] text-text-tertiary" data-selectable>
                      {signal.detail}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  )
}

function Header({
  status,
  onRecheck,
}: {
  status: RootStatusResponse
  onRecheck: () => void
}) {
  const { Icon, tint } = verdict(status)
  return (
    <div className="flex items-center gap-3.5">
      <Icon size={38} className={tint} />
      <div className="min-w-0 flex-1">
        <h2 className="text-[17px] font-bold text-text-primary">{status.summary}</h2>
        <p className="text-text-tertiary">
          {status.hasRootShell
            ? "A root shell is available over adb."
            : "Root-only features need a granted su shell."}
        </p>
      </div>
      <Button onClick={onRecheck}>
        <span className="flex items-center gap-1.5">
          <RefreshCw size={12} />
          Re-check
        </span>
      </Button>
    </div>
  )
}

/** The Mac's three-way icon and tint: granted, likely, neither. */
function verdict(status: RootStatusResponse) {
  if (status.hasRootShell) return { Icon: ShieldCheck, tint: "text-accent" }
  if (status.likelyRooted) return { Icon: ShieldAlert, tint: "text-warn" }
  return { Icon: ShieldQuestion, tint: "text-text-tertiary" }
}
