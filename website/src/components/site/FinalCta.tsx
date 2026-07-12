import { Download, Star } from "lucide-react"

import ShinyText from "@/components/ShinyText"
import { Reveal } from "@/components/site/Reveal"
import { Button } from "@/components/ui/button"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"
import { DOWNLOAD_URL, GITHUB_URL } from "@/lib/content"

export function FinalCta() {
  const reducedMotion = usePrefersReducedMotion()

  return (
    <section className="mx-auto max-w-[1120px] px-6 pb-26 max-[620px]:pb-18">
      <Reveal>
        <div className="relative overflow-hidden rounded-3xl border border-border-2 bg-[radial-gradient(600px_280px_at_50%_-10%,rgba(155,224,33,0.1),transparent_70%),var(--color-ink-800)] px-8 py-19 text-center">
          <h2 className="mb-3.5 text-[clamp(28px,4vw,40px)] font-extrabold tracking-[-0.03em]">
            {reducedMotion ? (
              "Debug Android without the terminal."
            ) : (
              <ShinyText
                text="Debug Android without the terminal."
                color="#e7eae5"
                shineColor="#b6f24a"
                speed={3}
                delay={1.5}
              />
            )}
          </h2>
          <p className="mb-7.5 text-[17px] text-muted">Free, open source, and one keystroke away.</p>
          <div className="flex flex-wrap justify-center gap-3.25">
            <Button
              asChild
              size="lg"
              className="h-auto rounded-xl px-5 py-3 text-[15px] font-bold shadow-glow transition-transform duration-150 hover:-translate-y-px hover:bg-green-bright"
            >
              <a href={DOWNLOAD_URL} data-dl="final-cta">
                <Download aria-hidden />
                Download for macOS
              </a>
            </Button>
            <Button
              asChild
              variant="outline"
              size="lg"
              className="h-auto rounded-xl border-border-2 bg-white/4 px-5 py-3 text-[15px] font-semibold transition-transform duration-150 hover:-translate-y-px hover:bg-white/8"
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
