import { Download, Star } from "lucide-react"

import BlurText from "@/components/BlurText"
import DotGrid from "@/components/DotGrid"
import { PaletteDemo } from "@/components/site/PaletteDemo"
import { Reveal } from "@/components/site/Reveal"
import { Button } from "@/components/ui/button"
import { useFinePointer } from "@/hooks/useFinePointer"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"
import { APP_VERSION, DOWNLOAD_URL, GITHUB_URL } from "@/lib/content"

export function Hero() {
  const reducedMotion = usePrefersReducedMotion()
  const finePointer = useFinePointer()
  const staticHeading = reducedMotion || !finePointer

  return (
    <header id="top" className="relative overflow-hidden pt-28 pb-24 max-[620px]:pt-22 max-[620px]:pb-18">
      {/* Atmospheric grid */}
      <div aria-hidden className="atmo-grid pointer-events-none absolute inset-0 opacity-60" />

      {/* Interactive dot field */}
      <div
        className="absolute inset-0 opacity-50 [mask-image:radial-gradient(900px_600px_at_50%_0%,black,transparent_80%)]"
        aria-hidden
      >
        {finePointer && !reducedMotion ? (
          <DotGrid
            dotSize={2}
            gap={28}
            baseColor="#1b1f1e"
            activeColor="#69a106"
            proximity={100}
            shockRadius={200}
            shockStrength={3.5}
          />
        ) : (
          <div className="h-full w-full bg-[radial-gradient(circle,#1b1f1e_1px,transparent_1px)] bg-[size:28px_28px]" />
        )}
      </div>

      {/* Primary green atmospheric glow */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-[20%] left-1/2 h-[700px] w-[1100px] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(105,161,6,0.18),transparent_70%)] opacity-60 blur-2xl"
      />
      {/* Secondary deep teal ambient */}
      <div
        aria-hidden
        className="pointer-events-none absolute top-[10%] left-1/4 h-[500px] w-[600px] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(16,60,80,0.12),transparent_70%)] blur-3xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute top-[15%] right-0 h-[400px] w-[500px] rounded-full bg-[radial-gradient(closest-side,rgba(30,50,90,0.08),transparent_70%)] blur-3xl"
      />

      <div className="relative mx-auto flex max-w-[1120px] flex-col items-center px-6 text-center">
        {/* Eyebrow */}
        <Reveal>
          <a
            href={`${GITHUB_URL}/releases/tag/${APP_VERSION}`}
            className="group mb-8 inline-flex items-center gap-2.25 rounded-full border border-white/[0.06] bg-white/[0.03] px-4 py-1.75 font-mono text-[12px] text-muted/90 transition-all duration-200 hover:border-green/20 hover:bg-green/[0.04] hover:text-text"
          >
            <span className="relative flex size-2">
              <span className="cta-breathe absolute inline-flex size-full rounded-full bg-green" />
              <span className="relative inline-flex size-2 rounded-full bg-green" />
            </span>
            {APP_VERSION} Released
            <span className="mx-1 text-white/10">|</span>
            Free &amp; Open Source · macOS 14+
            <span className="text-faint transition-colors duration-150 group-hover:text-green">→</span>
          </a>
        </Reveal>

        {/* Headline */}
        <h1 className="mb-7 max-w-[16ch] text-[clamp(40px,6vw,72px)] leading-[1.0] font-extrabold tracking-[-0.04em]">
          {staticHeading ? (
            <>
              All your Android debugging tools,{" "}
              <span className="text-green">one keystroke</span> away.
            </>
          ) : (
            <BlurText
              text="All your Android debugging tools, one keystroke away."
              animateBy="words"
              direction="top"
              delay={120}
              stepDuration={0.3}
              className="[&>span:nth-child(6)]:text-green [&>span:nth-child(7)]:text-green"
            />
          )}
        </h1>

        {/* Subheading */}
        <Reveal>
          <p className="mb-9 max-w-[54ch] text-[clamp(16px,1.6vw,19px)] leading-[1.7] text-muted">
            The complete{" "}
            <strong className="font-semibold text-text">ADB workflow</strong> for Android &amp; React Native —
            mirror screens, tail logcat, browse files, fake any state, and watch performance live.{" "}
            <strong className="font-semibold text-text">59 tools</strong>, no terminal required.
          </p>
        </Reveal>

        {/* CTAs */}
        <Reveal>
          <div className="mb-4 flex flex-wrap justify-center gap-3.5">
            <Button
              asChild
              size="lg"
              className="group/dl h-auto rounded-xl px-7 py-3.5 text-[15.5px] font-bold shadow-glow transition-all duration-200 hover:-translate-y-px hover:bg-green-bright hover:shadow-[0_0_0_1px_rgba(105,161,6,0.5),0_14px_40px_-8px_rgba(105,161,6,0.3)]"
            >
              <a href={DOWNLOAD_URL} data-dl="hero">
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
          <p className="mb-16 font-mono text-[12px] tracking-[0.02em] text-faint/80">
            Signed &amp; notarized · Apple Silicon &amp; Intel · Auto-updates via Sparkle
          </p>
        </Reveal>

        {/* Command Palette showcase */}
        <Reveal className="w-full max-w-[640px]">
          <div className="relative">
            {/* Ambient glow behind palette */}
            <div
              aria-hidden
              className="pointer-events-none absolute -inset-8 rounded-3xl bg-[radial-gradient(closest-side,rgba(105,161,6,0.06),transparent_70%)] blur-xl"
            />
            <PaletteDemo />
          </div>
        </Reveal>
      </div>
    </header>
  )
}
