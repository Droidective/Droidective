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
    <header id="top" className="relative overflow-hidden pt-19 pb-20">
      {/* Interactive dot field */}
      <div
        className="absolute inset-0 opacity-70 [mask-image:radial-gradient(1000px_700px_at_50%_0%,black,transparent_75%)]"
        aria-hidden
      >
        {finePointer && !reducedMotion ? (
          <DotGrid
            dotSize={2.5}
            gap={26}
            baseColor="#1b1f1e"
            activeColor="#9be021"
            proximity={110}
            shockRadius={220}
            shockStrength={4}
          />
        ) : (
          <div className="h-full w-full bg-[radial-gradient(circle,#1b1f1e_1.25px,transparent_1.25px)] bg-[size:28.5px_28.5px]" />
        )}
      </div>
      {/* Green glow behind content — centered */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-[15%] left-1/2 h-175 w-225 -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(155,224,33,0.25),transparent_70%)] opacity-55 blur-lg"
      />

      <div className="relative mx-auto flex max-w-[1120px] flex-col items-center px-6 text-center">
        {/* Eyebrow banner */}
        <a
          href={`${GITHUB_URL}/releases/tag/${APP_VERSION}`}
          className="group mb-7 inline-flex items-center gap-2.25 rounded-full border border-border bg-white/3 px-3.5 py-1.5 font-mono text-[12.5px] text-muted transition-colors duration-150 hover:border-green/30 hover:text-text"
        >
          <span className="size-1.75 shrink-0 rounded-full bg-green shadow-[0_0_10px_var(--color-green)]" />
          {APP_VERSION} Released · Free &amp; Open Source · macOS 14+
          <span className="text-faint transition-colors duration-150 group-hover:text-green">→</span>
        </a>

        <h1 className="mb-6 max-w-[18ch] text-[clamp(38px,5.8vw,68px)] leading-[1.02] font-extrabold tracking-[-0.035em]">
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

        <p className="mb-8 max-w-[58ch] text-[clamp(16px,1.5vw,19px)] leading-[1.65] text-muted">
          Droidective is a native macOS command palette for{" "}
          <strong className="font-semibold text-text">Android &amp; React Native</strong> debugging.
          Mirror screens, tail logcat, browse files, fake any state, and watch performance live —{" "}
          <strong className="font-semibold text-text">59 tools</strong>, no terminal required.
        </p>

        <div className="mb-3.5 flex flex-wrap justify-center gap-3.25">
          <Button
            asChild
            size="lg"
            className="h-auto rounded-xl px-6 py-3.5 text-[15.5px] font-bold shadow-glow transition-transform duration-150 hover:-translate-y-px hover:bg-green-bright"
          >
            <a href={DOWNLOAD_URL} data-dl="hero">
              <Download aria-hidden />
              Download for macOS
            </a>
          </Button>
          <Button
            asChild
            variant="outline"
            size="lg"
            className="h-auto rounded-xl border-border-2 bg-white/4 px-6 py-3.5 text-[15.5px] font-semibold transition-transform duration-150 hover:-translate-y-px hover:bg-white/8"
          >
            <a href={GITHUB_URL}>
              <Star aria-hidden />
              Star on GitHub
            </a>
          </Button>
        </div>

        <p className="mb-14 font-mono text-[12.5px] text-faint">
          Signed &amp; notarized · Apple Silicon &amp; Intel · Auto-updates via Sparkle
        </p>

        {/* Centered PaletteDemo */}
        <Reveal className="w-full max-w-[620px]">
          <PaletteDemo />
        </Reveal>
      </div>
    </header>
  )
}
