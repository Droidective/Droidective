import { ArrowRight } from "lucide-react"

import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { problemSolutions } from "@/lib/content"

export function Problems() {
  return (
    <section className="mx-auto max-w-[1120px] px-6 py-26 max-[620px]:py-18">
      <SectionHead center eyebrow="the problem" title="You already know the pain.">
        Every Android developer has the same set of daily frustrations. Droidective was built to solve them.
      </SectionHead>
      <div className="grid grid-cols-2 gap-4.5 max-[620px]:grid-cols-1">
        {problemSolutions.map((ps, i) => (
          <Reveal key={ps.problem} delay={Math.min(i % 2, 1) * 80}>
            <div className="group h-full min-w-0 rounded-2xl border border-border bg-linear-to-b from-white/2 to-white/0 p-7 transition-[border-color] duration-200 hover:border-green/30">
              <div className="mb-5 flex items-start gap-3">
                <span className="mt-0.5 shrink-0 rounded-lg border border-red-500/20 bg-red-500/8 px-2 py-0.75 font-mono text-[11px] font-medium text-red-400">
                  PROBLEM
                </span>
                <p className="text-[15.5px] font-semibold leading-snug text-text/80">{ps.problem}</p>
              </div>
              <div className="mb-4 flex items-center gap-2 text-faint">
                <ArrowRight className="size-3.5 text-green" aria-hidden />
                <span className="font-mono text-[11px] tracking-[0.04em] text-green">SOLUTION</span>
              </div>
              <h3 className="mb-2.5 text-[18px] font-bold tracking-[-0.01em]">{ps.solution}</h3>
              <p className="text-[14.5px] leading-relaxed text-muted">{ps.detail}</p>
            </div>
          </Reveal>
        ))}
      </div>
    </section>
  )
}
