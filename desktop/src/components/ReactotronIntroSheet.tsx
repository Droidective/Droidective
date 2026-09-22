import { useEffect } from "react"
import { Columns2, Radio } from "lucide-react"

import { Button } from "@/components/Controls"

/**
 * Shown the first time Reactotron opens, and only then — the Mac's
 * `ReactotronIntroSheet`.
 *
 * What it explains is the two things that set this screen apart from the other
 * log feeds: the app is the Reactotron *server*, and the timeline splits with a
 * filter per pane. Any dismissal marks it seen, as on the Mac — someone who
 * closed it does not get asked again.
 *
 * The Mac plays the recorded `tour-reactotron` clip above the text. There are no
 * tour recordings in this app, so the two ideas are drawn instead of filmed; the
 * wording is the Mac's, unchanged.
 */
export function ReactotronIntroSheet({ onDismiss }: { onDismiss: () => void }) {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      // Got it is the default action on the Mac, and Escape closes any sheet.
      if (event.key === "Escape" || event.key === "Enter") onDismiss()
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
        aria-label="Got it"
        onClick={onDismiss}
        className="absolute inset-0 cursor-default"
      />
      <dialog
        open
        aria-modal="true"
        aria-label="Reactotron, built in"
        className="relative flex w-[560px] max-w-full flex-col items-center gap-4 rounded-xl border border-border-subtle bg-bg-raised p-6 text-text-primary shadow-2xl"
      >
        <IntroArt />
        <h2 className="text-[19px] font-semibold text-text-primary">Reactotron, built in</h2>
        <p className="max-w-[440px] text-center text-[12.5px] leading-relaxed text-text-secondary">
          Droidective is the Reactotron server — your app&apos;s actions, API calls, and logs
          stream into this timeline live. Split it and give each pane its own filter: API traffic
          on one side, logs on the other.
        </p>
        <Button tone="primary" onClick={onDismiss}>
          Got it
        </Button>
      </dialog>
    </div>
  )
}

/** The two ideas the sentence names, drawn rather than filmed. */
function IntroArt() {
  return (
    <div className="flex w-full items-stretch gap-3">
      <IntroCard icon={<Radio size={15} />} title="The server is here">
        Point your app at this machine on :9090. Nothing else to install.
      </IntroCard>
      <IntroCard icon={<Columns2 size={15} />} title="Two panes, two filters">
        API traffic on one side, logs on the other, at the same time.
      </IntroCard>
    </div>
  )
}

function IntroCard({
  icon,
  title,
  children,
}: {
  icon: React.ReactNode
  title: string
  children: React.ReactNode
}) {
  return (
    <div className="flex flex-1 flex-col gap-1.5 rounded-lg border border-border-subtle bg-bg-surface p-3">
      <span className="flex items-center gap-1.5 text-accent">
        {icon}
        <span className="text-[12px] font-medium text-text-primary">{title}</span>
      </span>
      <span className="text-[11.5px] leading-snug text-text-tertiary">{children}</span>
    </div>
  )
}
