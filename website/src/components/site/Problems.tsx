import { ArrowRight } from "lucide-react"

import { MagicCard } from "@/components/MagicCard"
import { Reveal } from "@/components/site/Reveal"
import { problemSolutions } from "@/lib/content"

const chaosTools = ["Terminal", "adb", "logcat", "scrcpy", "Reactotron", "Monitor"]

export function Problems() {
  return (
    <section className="mx-auto max-w-[1120px] px-6 py-28 max-[620px]:py-20">
      {/* Chaos → Workspace narrative */}
      <Reveal className="mb-16 text-center">
        <div className="mx-auto mb-6 flex flex-wrap justify-center gap-2.5">
          {chaosTools.map((tool) => (
            <span
              key={tool}
              className="rounded-lg border border-white/[0.06] bg-white/[0.02] px-3.5 py-1.5 font-mono text-[12.5px] text-muted/70"
            >
              {tool}
            </span>
          ))}
        </div>
        <p className="mb-5 font-mono text-[12.5px] font-medium tracking-[0.06em] text-destructive/70 uppercase">
          too many tools · too many windows · too much context switching
        </p>
        <div className="mx-auto mb-5 flex items-center justify-center gap-3">
          <div className="h-px w-12 bg-gradient-to-r from-transparent to-white/10" />
          <span className="font-mono text-[13px] font-bold text-green">⌘T</span>
          <div className="h-px w-12 bg-gradient-to-l from-transparent to-white/10" />
        </div>
        <h2 className="text-[clamp(28px,4.5vw,48px)] leading-[1.04] font-extrabold tracking-[-0.035em]">
          One workspace.{" "}
          <span className="text-green">One keystroke.</span>
        </h2>
        <p className="mx-auto mt-4 max-w-[52ch] text-lg text-muted">
          Every tool you juggle today lives behind a single command palette.
          No more alt-tabbing between debugging windows.
        </p>
      </Reveal>

      {/* Problem → Solution cards */}
      <div className="grid grid-cols-2 gap-4 max-[620px]:grid-cols-1">
        {problemSolutions.map((ps, i) => (
          <Reveal key={ps.solution} delay={i * 60}>
            <MagicCard className="h-full">
              <div className="flex h-full flex-col p-6 pb-5.5">
                <div className="mb-4 flex items-start gap-3">
                  <span className="mt-0.5 shrink-0 font-mono text-[32px] font-bold leading-none text-white/[0.06]">
                    {String(i + 1).padStart(2, "0")}
                  </span>
                  <div className="min-w-0">
                    <span className="mb-2 inline-block rounded-md bg-destructive/10 px-2 py-0.5 font-mono text-[10.5px] font-bold tracking-[0.06em] text-destructive/80 uppercase">
                      Problem
                    </span>
                    <p className="text-[14.5px] leading-snug text-muted">{ps.problem}</p>
                  </div>
                </div>
                <div className="mt-auto border-t border-white/[0.04] pt-4">
                  <div className="mb-2 flex items-center gap-2">
                    <ArrowRight className="size-3.5 text-green" aria-hidden />
                    <span className="font-mono text-[10.5px] font-bold tracking-[0.06em] text-green/80 uppercase">
                      Solution
                    </span>
                  </div>
                  <p className="mb-1.5 text-[15px] font-semibold tracking-[-0.01em]">{ps.solution}</p>
                  <p className="text-[13.5px] leading-relaxed text-muted/80">{ps.detail}</p>
                </div>
              </div>
            </MagicCard>
          </Reveal>
        ))}
      </div>
    </section>
  )
}
