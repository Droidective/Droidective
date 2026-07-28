import { MagicCard } from "@/components/MagicCard"
import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"

const steps = [
  {
    n: "01",
    label: "setup",
    title: "Install adb",
    body: "Droidective finds the Android platform-tools automatically. If they're missing, it points you to the install.",
    code: (
      <>
        <span className="text-green">$</span> brew install android-platform-tools
      </>
    ),
  },
  {
    n: "02",
    label: "connect",
    title: "Plug in your device",
    body: "Connect over USB, or go wireless with the built-in pairing wizard. Emulators show up automatically.",
    code: (
      <>
        <span className="text-green">$</span> adb devices{"\n"}List of devices attached{"\n"}Pixel 8     device
      </>
    ),
  },
  {
    n: "03",
    label: "go",
    title: "Press ⌘T and run",
    body: "Search any of the 59 tools and run it. The Setup Doctor confirms your toolchain on first launch.",
    code: (
      <>
        <span className="text-green">⌘T</span> mirror screen   ↩
      </>
    ),
  },
]

export function HowItWorks() {
  return (
    <section id="how" className="mx-auto max-w-[1120px] px-6 py-28 max-[620px]:py-20">
      <SectionHead center eyebrow="how it works" title="Connected in under a minute.">
        Three steps. The app handles the rest — it even finds adb for you and offers a one-click install if it's
        missing.
      </SectionHead>
      <div className="grid grid-cols-3 gap-4 max-[620px]:grid-cols-1">
        {steps.map((step, i) => (
          <Reveal key={step.n} delay={i * 80}>
            <MagicCard className="h-full">
              <div className="flex h-full min-w-0 flex-col p-6">
                <div className="mb-4 flex items-baseline gap-2">
                  <span className="font-mono text-[24px] font-bold text-green/30">{step.n}</span>
                  <span className="font-mono text-[11px] tracking-[0.06em] text-green/60 uppercase">{step.label}</span>
                </div>
                <h4 className="mb-2 text-[17px] font-semibold tracking-[-0.01em]">{step.title}</h4>
                <p className="mb-4 flex-1 text-[14px] leading-relaxed text-muted/90">{step.body}</p>
                <pre className="m-0 max-w-full rounded-[10px] border border-white/[0.06] bg-ink-900/60 px-3.5 py-3 font-mono text-[12px] break-words whitespace-pre-wrap text-[#cdd5cb]">
                  {step.code}
                </pre>
              </div>
            </MagicCard>
          </Reveal>
        ))}
      </div>
    </section>
  )
}
