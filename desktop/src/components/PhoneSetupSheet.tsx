import { useEffect, useRef, useState } from "react"
import { Check, Circle, CircleCheck, CircleMinus, CircleX, LoaderCircle, Smartphone } from "lucide-react"
import { Button } from "@/components/Controls"
import { asDaemonError, phoneSetupStatus, watchPhoneSetup, type Subscription } from "@/lib/daemon"
import { cn } from "@/lib/cn"
import { SUBTITLE, actionTitle, setupRows, streamedStatus, type RowKind } from "@/lib/phone-setup"
import type { PhoneSetupOffer, PhoneSetupProgress, PhoneSetupStatus, StreamUpdate } from "@/lib/wire"

interface Result {
  ok: boolean
  message: string
}

/**
 * One-click set-up of Droidective for Android — the Mac's `PhoneSetupSheet`.
 *
 * Three rows for what is done, and one button that installs or updates the
 * app from its latest release when the phone needs it, grants the permissions
 * only adb can, and starts Shizuku if it is stopped. The daemon does all of it
 * (the `phonesetup` topic over ADBKit's `PhoneAppSetupService`); this shows its
 * answers, each stage as it happens, and adb's reason inline when a step fails.
 */
export function PhoneSetupSheet({
  serial,
  name,
  onOffer,
  onDismiss,
}: {
  serial: string
  name: string
  /** What the device menu should offer after every read, so it changes at once. */
  onOffer: (offer: PhoneSetupOffer | null) => void
  onDismiss: () => void
}) {
  const { status, checking, busy, stage, result, run } = usePhoneSetup(serial, onOffer)

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
          <ResultLine busy={busy} stage={stage} checking={checking} result={result} status={status} />
          <span className="flex-1" />
          <Button onClick={onDismiss}>Close</Button>
          <Button tone="primary" disabled={busy || status?.hasWork !== true} onClick={run}>
            {actionTitle(status)}
          </Button>
        </div>
      </dialog>
    </div>
  )
}

/** The first read, then the one run, and what each said. */
function usePhoneSetup(serial: string, onOffer: (offer: PhoneSetupOffer | null) => void) {
  const [status, setStatus] = useState<PhoneSetupStatus | null>(null)
  const [checking, setChecking] = useState(true)
  const [busy, setBusy] = useState(false)
  const [stage, setStage] = useState<string | null>(null)
  const [result, setResult] = useState<Result | null>(null)
  // A run outlives the sheet, as the Mac's does; only its updates stop.
  const mounted = useRef(true)
  useEffect(() => {
    mounted.current = true
    return () => {
      mounted.current = false
    }
  }, [])

  useEffect(() => {
    let live = true
    void (async () => {
      try {
        const read = await phoneSetupStatus(serial, false)
        if (!live) return
        setStatus(read)
        onOffer(read.offer)
      } catch (thrown) {
        if (live) setResult({ ok: false, message: asDaemonError(thrown).message })
      } finally {
        if (live) setChecking(false)
      }
    })()
    return () => {
      live = false
    }
    // The sheet reads once per phone; `onOffer` is the bar's setter.
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [serial])

  const run = () => {
    setBusy(true)
    setStage(null)
    setResult(null)
    let subscription: Subscription | null = null
    let ended = false
    const finish = (outcome: Result | null) => {
      ended = true
      void subscription?.stop()
      if (!mounted.current) return
      if (outcome !== null) setResult(outcome)
      setBusy(false)
    }
    const onUpdate = (update: StreamUpdate<PhoneSetupProgress>) => {
      if (update.event === "batch") {
        for (const item of update.items) {
          if (item.done === true) {
            const read = item.status === undefined ? null : streamedStatus(item.status)
            if (read !== null) onOffer(read.offer)
            if (mounted.current && read !== null) setStatus(read)
            finish(
              item.failure === undefined
                ? { ok: true, message: "All set." }
                : { ok: false, message: item.failure },
            )
          } else if (item.stage !== undefined && mounted.current) {
            setStage(item.stage)
          }
        }
      } else if (update.event === "failed") {
        finish({ ok: false, message: update.message })
      } else if (update.event === "ended" && !ended) {
        finish({ ok: false, message: "The set-up stopped before it finished." })
      }
    }
    watchPhoneSetup(serial, onUpdate).then(
      (started) => {
        subscription = started
        if (ended) void started.stop()
      },
      (thrown: unknown) => {
        finish({ ok: false, message: asDaemonError(thrown).message })
      },
    )
  }

  return { status, checking, busy, stage, result, run }
}

function Header({ name }: { name: string }) {
  return (
    <header className="flex items-start gap-3">
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-accent/12 text-accent">
        <Smartphone size={17} />
      </span>
      <div className="min-w-0">
        <h2 className="text-[14px] font-medium text-text-primary">Set Up Droidective on {name}</h2>
        <p className="mt-0.5 text-[12px] text-text-secondary">{SUBTITLE}</p>
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
  stage,
  checking,
  result,
  status,
}: {
  busy: boolean
  stage: string | null
  checking: boolean
  result: Result | null
  status: PhoneSetupStatus | null
}) {
  if (busy || checking) {
    return (
      <span className="text-[12px] text-text-tertiary">
        {busy ? (stage ?? "Setting up…") : "Checking the phone…"}
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
  if (status !== null && status.appInstalled && !status.hasWork) {
    return (
      <span className="text-[12px] text-text-tertiary">Nothing to do — this phone is set up.</span>
    )
  }
  return null
}
