import { ArrowRight, Download } from "lucide-react"

import BlurText from "@/components/BlurText"
import DotGrid from "@/components/DotGrid"
import { PaletteDemo } from "@/components/site/PaletteDemo"
import { Reveal } from "@/components/site/Reveal"
import { Button } from "@/components/ui/button"
import { useFinePointer } from "@/hooks/useFinePointer"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"
import { DOWNLOAD_URL } from "@/lib/content"

export function Hero() {
  const reducedMotion = usePrefersReducedMotion()
  const finePointer = useFinePointer()
  const staticHeading = reducedMotion || !finePointer

  return (
    <header id="top" className="relative overflow-hidden pt-30 pb-24 max-[620px]:pt-24 max-[620px]:pb-16">
      <div aria-hidden className="atmo-grid pointer-events-none absolute inset-0 opacity-50" />

      <div
        className="absolute inset-0 opacity-45 [mask-image:radial-gradient(880px_580px_at_50%_0%,black,transparent_80%)]"
        aria-hidden
      >
        {finePointer && !reducedMotion ? (
          <DotGrid
            dotSize={2}
            gap={30}
            baseColor="#1b1f1e"
            activeColor="#69a106"
            proximity={100}
            shockRadius={190}
            shockStrength={3}
          />
        ) : (
          <div className="h-full w-full bg-[radial-gradient(circle,#1b1f1e_1px,transparent_1px)] bg-[size:30px_30px]" />
        )}
      </div>

      {/* Primary brand glow + two very low-opacity cool washes for depth */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-[22%] left-1/2 h-[680px] w-[1050px] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(105,161,6,0.16),transparent_70%)] opacity-60 blur-2xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute top-[12%] left-[22%] h-[460px] w-[560px] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(16,58,78,0.1),transparent_70%)] blur-3xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute top-[16%] right-0 h-[380px] w-[460px] rounded-full bg-[radial-gradient(closest-side,rgba(28,46,84,0.07),transparent_70%)] blur-3xl"
      />

      <div className="relative mx-auto flex max-w-[1120px] flex-col items-center px-6 text-center">
        {/* Eyebrow */}
        <Reveal>
          <p className="mb-7 font-mono text-[11.5px] font-medium tracking-[0.14em] text-green/70 uppercase max-[620px]:tracking-[0.1em]">
            Android &amp; React Native, without the terminal
          </p>
        </Reveal>

        {/* Headline */}
        <h1 className="display mb-7 max-w-[19ch] text-[clamp(38px,6vw,74px)] leading-[0.99] font-semibold tracking-[-0.045em]">
          {staticHeading ? (
            <>
              Everything between your code and your{" "}
              <span className="text-green">running app.</span>
            </>
          ) : (
            /* BlurText lays its words out with `flex flex-wrap`, which defaults
               to justify-content:flex-start — so the parent's text-center has no
               effect and wrapped lines sit left. justify-center fixes it. */
            <BlurText
              text="Everything between your code and your running app."
              animateBy="words"
              direction="top"
              delay={100}
              stepDuration={0.3}
              className="justify-center [&>span:nth-child(7)]:text-green [&>span:nth-child(8)]:text-green"
            />
          )}
        </h1>

        {/* Subheading */}
        <Reveal>
          <p className="prose-balance mb-9 max-w-[54ch] text-[clamp(15.5px,1.6vw,18.5px)] leading-[1.7] text-muted">
            Mirroring, logs, React Native tooling, performance and APK workflows.{" "}
            <strong className="font-semibold text-text tnum">61 tools</strong> in one native
            workspace, no terminal required.
          </p>
        </Reveal>

        {/* CTAs */}
        <Reveal>
          <div className="mb-16 flex flex-wrap items-center justify-center gap-3.5">
            <Button
              asChild
              size="lg"
              className="group/dl h-auto rounded-full py-2.5 pr-2.5 pl-7 text-[15.5px] font-semibold shadow-glow transition-all duration-700 ease-[cubic-bezier(0.32,0.72,0,1)] hover:-translate-y-0.5 hover:bg-green-bright hover:shadow-[0_0_0_1px_rgba(105,161,6,0.5),0_14px_40px_-8px_rgba(105,161,6,0.3)] active:scale-[0.98]"
            >
              <a href={DOWNLOAD_URL} data-dl="hero">
                Download for macOS
                <span
                  aria-hidden
                  className="ml-1 flex size-7 items-center justify-center rounded-full bg-ink-900/20 transition-all duration-700 ease-[cubic-bezier(0.32,0.72,0,1)] group-hover/dl:scale-105 group-hover/dl:bg-ink-900/30"
                >
                  <Download className="size-3.5 transition-transform duration-700 ease-[cubic-bezier(0.32,0.72,0,1)] group-hover/dl:translate-y-px" />
                </span>
              </a>
            </Button>
            <Button
              asChild
              variant="outline"
              size="lg"
              className="group/ex h-auto rounded-full border-white/[0.08] bg-white/[0.03] px-7 py-3.5 text-[15.5px] font-medium transition-all duration-700 ease-[cubic-bezier(0.32,0.72,0,1)] hover:-translate-y-0.5 hover:border-white/[0.14] hover:bg-white/[0.06] active:scale-[0.98]"
            >
              <a href="#workflows">
                Explore features
                <ArrowRight
                  className="transition-transform duration-200 group-hover/ex:translate-x-0.5"
                  aria-hidden
                />
              </a>
            </Button>
          </div>

        </Reveal>

        {/* The one hero product visual */}
        <Reveal className="w-full max-w-[640px]">
          <div className="relative">
            <div
              aria-hidden
              className="pointer-events-none absolute -inset-10 rounded-[32px] bg-[radial-gradient(closest-side,rgba(105,161,6,0.07),transparent_70%)] blur-xl"
            />
            <PaletteDemo />
          </div>
        </Reveal>
      </div>
    </header>
  )
}
