import { useEffect, useState } from "react"
import { Check, Circle, CircleCheck, CircleMinus, CircleX, LoaderCircle, Smartphone } from "lucide-react"
import { Button } from "@/components/Controls"
import { asDaemonError, phoneSetupStatus, setUpPhone } from "@/lib/daemon"
import { cn } from "@/lib/cn"
import { setupRows, type RowKind } from "@/lib/phone-setup"
import type { PhoneSetupStatus } from "@/lib/wire"

interface Result {
  ok: boolean
  message: string
}

/**
 * One-click set-up of Droidective for Android — the Mac's `PhoneSetupSheet`.
 *
 * Three rows for what is done, and one button that grants the two permissions
 * only adb can and starts Shizuku if it is stopped. The daemon does all of it
 * (`/v1/phonesetup/run` over ADBKit's `PhoneAppSetupService`); this shows its
 * answers, and adb's reason inline when a step fails.
 */
export function PhoneSetupSheet({
  serial,
  name,
  onStatus,
  onDismiss,
}: {
  serial: string
  name: string
  /** Every status read, so the device menu stops offering set-up once it is done. */
  onStatus: (status: PhoneSetupStatus) => void
  onDismiss: () => void
}) {
  const { status, checking, busy, result, run } = usePhoneSetup(serial, onStatus)

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onDismiss()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onDismiss])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      <button
        type="button"
        aria-label="Close"
        onClick={onDismiss}
        className="absolute inset-0 cursor-default"
      />
      <dialog
        open
        aria-label="Set Up Droidective"
        className={cn(
          "relative m-0 flex w-[460px] max-w-full flex-col gap-3.5 p-5",
          "rounded-xl border border-border-subtle bg-bg-raised text-text-primary shadow-2xl",
        )}
      >
        <Header name={name} />

        <ul className="flex flex-col gap-3">
          {setupRows(status, checking).map((row) => (
            <li key={row.title} className="flex items-start gap-2.5">
              <RowGlyph kind={row.kind} />
              <div className="min-w-0">
                <p className="text-[12.5px] font-semibold text-text-primary">{row.title}</p>
                <p className="text-[12px] text-text-secondary">{row.detail}</p>
              </div>
            </li>
          ))}
        </ul>

        <div className="h-px bg-border-subtle" />

        <div className="flex items-start gap-2">
          <ResultLine busy={busy} checking={checking} result={result} status={status} />
          <span className="flex-1" />
          <Button onClick={onDismiss}>Close</Button>
          <Button tone="primary" disabled={busy || status?.needsSetup !== true} onClick={run}>
            Set Up
          </Button>
        </div>
      </dialog>
    </div>
  )
}

/** The first read, then the one call, and what each said. */
function usePhoneSetup(serial: string, onStatus: (status: PhoneSetupStatus) => void) {
  const [status, setStatus] = useState<PhoneSetupStatus | null>(null)
  const [checking, setChecking] = useState(true)
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<Result | null>(null)

  useEffect(() => {
    let live = true
    void (async () => {
      try {
        const read = await phoneSetupStatus(serial, false)
        if (!live) return
        setStatus(read)
        onStatus(read)
      } catch (thrown) {
        if (live) setResult({ ok: false, message: asDaemonError(thrown).message })
      } finally {
        if (live) setChecking(false)
      }
    })()
    return () => {
      live = false
    }
    // The sheet reads once per phone; `onStatus` is the bar's setter.
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [serial])

  const run = () => {
    setBusy(true)
    setResult(null)
    void (async () => {
      try {
        const outcome = await setUpPhone(serial)
        setStatus(outcome.status)
        onStatus(outcome.status)
        setResult(
          outcome.failure === null
            ? { ok: true, message: "All set." }
            : { ok: false, message: outcome.failure },
        )
      } catch (thrown) {
        setResult({ ok: false, message: asDaemonError(thrown).message })
      } finally {
        setBusy(false)
      }
    })()
  }

  return { status, checking, busy, result, run }
}

function Header({ name }: { name: string }) {
  return (
    <header className="flex items-start gap-3">
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-accent/12 text-accent">
        <Smartphone size={17} />
      </span>
      <div className="min-w-0">
        <h2 className="text-[14px] font-medium text-text-primary">Set Up Droidective on {name}</h2>
        <p className="mt-0.5 text-[12px] text-text-secondary">
          Grants the app two permissions only adb can, and starts Shizuku if it&rsquo;s there.
        </p>
      </div>
    </header>
  )
}

function RowGlyph({ kind }: { kind: RowKind }) {
  const glyphs: Record<RowKind, React.ReactNode> = {
    checking: <LoaderCircle size={15} className="animate-spin text-text-tertiary" />,
    done: <CircleCheck size={15} className="text-accent" />,
    todo: <Circle size={15} className="text-text-tertiary" />,
    unavailable: <CircleMinus size={15} className="text-text-tertiary" />,
  }
  return (
    <span className="mt-px shrink-0" aria-label={kind}>
      {glyphs[kind]}
    </span>
  )
}

function ResultLine({
  busy,
  checking,
  result,
  status,
}: {
  busy: boolean
  checking: boolean
  result: Result | null
  status: PhoneSetupStatus | null
}) {
  if (busy || checking) {
    return (
      <span className="text-[12px] text-text-tertiary">
        {busy ? "Setting up…" : "Checking the phone…"}
      </span>
    )
  }
  if (result !== null) {
    return (
      <p
        className={cn(
          "flex min-w-0 items-start gap-1.5 text-[12px]",
          result.ok ? "text-text-primary" : "text-danger",
        )}
        data-selectable
      >
        <span className={cn("mt-px shrink-0", result.ok ? "text-accent" : "text-danger")}>
          {result.ok ? <Check size={13} /> : <CircleX size={13} />}
        </span>
        {result.message}
      </p>
    )
  }
  if (status !== null && status.appInstalled && !status.needsSetup) {
    return (
      <span className="text-[12px] text-text-tertiary">Nothing to do — this phone is set up.</span>
    )
  }
  return null
}
