import CountUp from "@/components/CountUp"
import { Reveal } from "@/components/site/Reveal"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"

/** A confidence signal, not a section: one enclosed row that reads in under two
 *  seconds. Bordered on all four sides to echo the header pill. */
export function TrustStrip() {
  const reducedMotion = usePrefersReducedMotion()

  return (
    <section className="px-6 pb-6">
      <Reveal className="mx-auto max-w-[1020px]">
        <div className="flex flex-wrap items-center justify-center gap-x-6 gap-y-3 rounded-2xl border border-white/[0.07] bg-white/[0.015] px-6 py-5 font-mono text-[12px] text-muted/75 max-[620px]:gap-x-4 max-[620px]:px-4 max-[620px]:text-[11px]">
          <span className="inline-flex items-baseline gap-1.5">
            <b className="text-[15px] font-bold text-green">
              {reducedMotion ? 59 : <CountUp to={59} duration={1.4} />}+
            </b>
            developer tools
          </span>
          <span aria-hidden className="text-white/10">
            ·
          </span>
          <span>Native macOS</span>
          <span aria-hidden className="text-white/10">
            ·
          </span>
          <span>Android + React Native</span>
          <span aria-hidden className="text-white/10">
            ·
          </span>
          <span>Free &amp; Open Source</span>
          <span aria-hidden className="text-white/10 max-[620px]:hidden">
            ·
          </span>
          <span className="max-[620px]:hidden">Signed &amp; Notarized</span>
        </div>
      </Reveal>
    </section>
  )
}
