import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"

const steps = [
  {
    n: "01 / setup",
    title: "Install adb",
    body: "Droidective finds the Android platform-tools automatically. If they're missing, it installs them for you:",
    code: (
      <>
        <span className="text-green">$</span> brew install android-platform-tools
      </>
    ),
  },
  {
    n: "02 / connect",
    title: "Plug in your device",
    body: "Connect over USB, or go wireless with the built-in pairing wizard. Emulators show up automatically.",
    code: (
      <>
        <span className="text-green">$</span> adb devices{"\n"}List of devices attached{"\n"}Pixel 8     device
      </>
    ),
  },
  {
    n: "03 / go",
    title: "Press ⌘T and run",
    body: "Search any of the 56 tools and run it. The Setup Doctor confirms your toolchain on first launch.",
    code: (
      <>
        <span className="text-green">⌘T</span> mirror screen   ↩
      </>
    ),
  },
]

export function HowItWorks() {
  return (
    <section id="how" className="mx-auto max-w-[1120px] px-6 py-26 max-[620px]:py-18">
      <SectionHead center eyebrow="how it works" title="Connected in under a minute.">
        Three steps. The app handles the rest — it even finds adb for you and offers a one-click install if it's
        missing.
      </SectionHead>
      <div className="grid grid-cols-3 gap-4.5 max-[620px]:grid-cols-1">
        {steps.map((step, i) => (
          <Reveal key={step.n} delay={i * 80}>
            <div className="h-full min-w-0 rounded-2xl border border-border bg-white/2 p-6">
              <span className="font-mono text-[13px] font-bold text-green">{step.n}</span>
              <h4 className="mt-3.5 mb-2 text-lg font-semibold tracking-[-0.01em]">{step.title}</h4>
              <p className="mb-3.5 text-[14.5px] text-muted">{step.body}</p>
              <pre className="m-0 max-w-full rounded-[10px] border border-border bg-ink-900 px-3.5 py-3 font-mono text-[12.5px] break-words whitespace-pre-wrap text-[#cdd5cb]">
                {step.code}
              </pre>
            </div>
          </Reveal>
        ))}
      </div>
    </section>
  )
}
