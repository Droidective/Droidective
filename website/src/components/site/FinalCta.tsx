import { useRef } from "react"

import { Download, Star } from "lucide-react"
import { useInView } from "motion/react"

import ShinyText from "@/components/ShinyText"
import { Reveal } from "@/components/site/Reveal"
import { Button } from "@/components/ui/button"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"
import { DOWNLOAD_URL, GITHUB_URL } from "@/lib/content"

export function FinalCta() {
  const reducedMotion = usePrefersReducedMotion()
  const headingRef = useRef<HTMLHeadingElement>(null)
  const inView = useInView(headingRef)

  return (
    <section className="mx-auto max-w-[1120px] px-6 pb-28 max-[620px]:pb-20">
      <Reveal>
        <div className="relative overflow-hidden rounded-3xl border border-white/[0.06] bg-gradient-to-b from-ink-700/60 to-ink-800/60 px-8 py-22 text-center shadow-[0_40px_100px_-30px_rgba(0,0,0,0.5)]">
          {/* Atmospheric green glow */}
          <div
            aria-hidden
            className="pointer-events-none absolute -top-20 left-1/2 h-40 w-[70%] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(105,161,6,0.1),transparent_70%)] blur-2xl"
          />

          <h2 ref={headingRef} className="display mb-4 text-[clamp(28px,4vw,44px)]">
            {reducedMotion || !inView ? (
              "Debug Android without the terminal."
            ) : (
              <ShinyText
                text="Debug Android without the terminal."
                color="#e7eae5"
                shineColor="#84c610"
                speed={3}
                delay={1.5}
              />
            )}
          </h2>
          <p className="mb-9 text-[17px] text-muted">
            Free, open source, and one keystroke away. Join thousands of developers.
          </p>
          <div className="flex flex-wrap justify-center gap-3.5">
            <Button
              asChild
              size="lg"
              className="group/dl h-auto rounded-xl px-7 py-3.5 text-[15.5px] font-bold shadow-glow transition-all duration-200 hover:-translate-y-px hover:bg-green-bright hover:shadow-[0_0_0_1px_rgba(105,161,6,0.5),0_14px_40px_-8px_rgba(105,161,6,0.3)]"
            >
              <a href={DOWNLOAD_URL} data-dl="final-cta">
                <Download className="transition-transform duration-200 group-hover/dl:-translate-y-px" aria-hidden />
                Download for macOS
              </a>
            </Button>
            <Button
              asChild
              variant="outline"
              size="lg"
              className="h-auto rounded-xl border-white/[0.08] bg-white/[0.03] px-7 py-3.5 text-[15.5px] font-semibold transition-all duration-200 hover:-translate-y-px hover:border-white/[0.14] hover:bg-white/[0.06]"
            >
              <a href={GITHUB_URL}>
                <Star aria-hidden />
                Star on GitHub
              </a>
            </Button>
          </div>
        </div>
      </Reveal>
    </section>
  )
}
