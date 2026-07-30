import { ArrowRight } from "lucide-react"

import { Reveal } from "@/components/site/Reveal"
import { comparisonRows } from "@/lib/content"

const oldStack = ["Terminal", "adb", "logcat", "scrcpy", "Reactotron", "Android Studio", "jadx"]

/** Category-level comparison — "the old workflow" is a set of tools, never a
 *  named competitor being called worse. */
export function Comparison() {
  return (
    <section id="why" className="mx-auto max-w-[1120px] px-6 py-32 max-[620px]:py-20">
      <Reveal className="mb-14 max-w-[62ch]">
        <span className="font-mono text-[12px] font-medium tracking-[0.06em] text-green/80 uppercase">
          <span className="mr-2 text-green-dim/60">&gt;_</span>
          why droidective
        </span>
        <h2 className="mt-4 mb-4 text-[clamp(28px,4.2vw,46px)] leading-[1.04] font-extrabold tracking-[-0.035em]">
          The better alternative to tool-hopping.
        </h2>
        <p className="text-lg leading-relaxed text-muted">
          Every one of these tools is good at its job. The cost isn't any single one — it's the seven
          windows, the lost context, and the command you look up for the hundredth time.
        </p>
      </Reveal>

      {/* The two stacks, side by side */}
      <Reveal className="mb-6">
        <div className="grid grid-cols-[1fr_auto_1fr] items-stretch gap-5 max-[940px]:grid-cols-1">
          <div className="rounded-2xl border border-white/[0.06] bg-white/[0.015] p-6">
            <p className="mb-4 font-mono text-[11px] tracking-[0.08em] text-faint/70 uppercase">the old workflow</p>
            <div className="mb-5 flex flex-wrap gap-2">
              {oldStack.map((t) => (
                <span
                  key={t}
                  className="rounded-lg border border-white/[0.06] bg-white/[0.02] px-2.5 py-1 font-mono text-[11.5px] text-muted/60"
                >
                  {t}
                </span>
              ))}
            </div>
            <p className="font-mono text-[13px] text-muted/50">7 windows open.</p>
          </div>

          <div aria-hidden className="grid place-items-center max-[940px]:py-1">
            <span className="grid size-9 place-items-center rounded-full border border-green/20 bg-green/[0.07] text-green max-[940px]:rotate-90">
              <ArrowRight className="size-4" />
            </span>
          </div>

          <div className="rounded-2xl border border-green/15 bg-green/[0.03] p-6">
            <p className="mb-4 font-mono text-[11px] tracking-[0.08em] text-green/70 uppercase">droidective</p>
            <div className="mb-5 flex flex-wrap gap-2">
              <span className="rounded-lg border border-green/20 bg-green/[0.08] px-2.5 py-1 font-mono text-[11.5px] text-green/90">
                One native macOS workspace
              </span>
            </div>
            <p className="font-mono text-[13px] text-green/60">1 app open.</p>
          </div>
        </div>
      </Reveal>

      {/* Row-by-row breakdown */}
      <Reveal>
        <div className="overflow-hidden rounded-2xl border border-white/[0.06]">
          <div className="grid grid-cols-[1fr_1.2fr_1.2fr] border-b border-white/[0.06] bg-white/[0.02] max-[620px]:hidden">
            {["Workflow", "Traditional setup", "Droidective"].map((h, i) => (
              <div
                key={h}
                className={`px-5 py-3 font-mono text-[10.5px] tracking-[0.08em] uppercase ${i === 2 ? "text-green/70" : "text-faint/60"}`}
              >
                {h}
              </div>
            ))}
          </div>
          {comparisonRows.map((row) => (
            <div
              key={row.workflow}
              className="grid grid-cols-[1fr_1.2fr_1.2fr] border-b border-white/[0.04] transition-colors duration-150 last:border-0 hover:bg-white/[0.015] max-[620px]:grid-cols-1 max-[620px]:gap-1 max-[620px]:py-3"
            >
              <div className="px-5 py-3.5 text-[13.5px] font-semibold max-[620px]:py-1">{row.workflow}</div>
              <div className="px-5 py-3.5 text-[13.5px] text-muted/60 max-[620px]:py-1">
                <span className="hidden font-mono text-[10px] text-faint/50 uppercase max-[620px]:mr-2 max-[620px]:inline">
                  before
                </span>
                {row.old}
              </div>
              <div className="px-5 py-3.5 text-[13.5px] text-text/90 max-[620px]:py-1">
                <span className="hidden font-mono text-[10px] text-green/50 uppercase max-[620px]:mr-2 max-[620px]:inline">
                  after
                </span>
                {row.nu}
              </div>
            </div>
          ))}
        </div>
      </Reveal>
    </section>
  )
}
