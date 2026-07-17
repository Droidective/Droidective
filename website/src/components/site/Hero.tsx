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
  // The dot field reacts to the mouse; on touch devices it would just burn
  // battery in a rAF loop, so those get the same field painted in CSS.
  const finePointer = useFinePointer()
  const staticHeading = reducedMotion || !finePointer

  return (
    <header id="top" className="relative overflow-hidden pt-19 pb-16">
      {/* Interactive dot field, masked so it fades toward the content */}
      <div
        className="absolute inset-0 opacity-70 [mask-image:radial-gradient(900px_600px_at_70%_0%,black,transparent_75%)]"
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
      {/* Green glow behind the palette */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-[20%] right-0 h-175 w-225 rounded-full bg-[radial-gradient(closest-side,rgba(155,224,33,0.3),transparent_70%)] opacity-55 blur-lg"
      />

      <div className="relative mx-auto grid max-w-[1120px] items-center gap-14 px-6 max-[940px]:grid-cols-1 max-[940px]:gap-11 min-[940px]:grid-cols-[0.92fr_1.08fr]">
        <div>
          <span className="mb-6 inline-flex items-center gap-2.25 rounded-full border border-border bg-white/3 px-3.25 py-1.5 font-mono text-[12.5px] text-muted max-[620px]:items-start max-[620px]:rounded-xl">
            <span className="size-1.75 shrink-0 rounded-full bg-green shadow-[0_0_10px_var(--color-green)] max-[620px]:mt-1.5" />
            Free &amp; open source · Signed &amp; notarized · macOS 14+ · Apple Silicon &amp; Intel
          </span>
          <h1 className="mb-5.5 max-w-[14ch] text-[clamp(38px,5.4vw,62px)] leading-[1.02] font-extrabold tracking-[-0.035em] max-[940px]:max-w-[18ch]">
            {staticHeading ? (
              <>
                Every adb tool, <span className="text-green">one keystroke</span> away.
              </>
            ) : (
              // words 4 & 5 ("one keystroke") carry the accent color
              <BlurText
                text="Every adb tool, one keystroke away."
                animateBy="words"
                direction="top"
                delay={120}
                stepDuration={0.3}
                className="[&>span:nth-child(4)]:text-green [&>span:nth-child(5)]:text-green"
              />
            )}
          </h1>
          <p className="mb-7.5 max-w-[52ch] text-[clamp(16px,1.5vw,19px)] text-muted">
            Droidective is a native macOS command palette for{" "}
            <strong className="font-semibold text-text">Android &amp; React Native</strong> debugging over adb.
            Mirror screens, tail logcat, browse device files, fake any state, and watch performance live —{" "}
            <strong className="font-semibold text-text">56 tools</strong>, no terminal required.
          </p>
          <div className="flex flex-wrap gap-3.25">
            <Button
              asChild
              size="lg"
              className="h-auto rounded-xl px-5 py-3 text-[15px] font-bold shadow-glow transition-transform duration-150 hover:-translate-y-px hover:bg-green-bright"
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
              className="h-auto rounded-xl border-border-2 bg-white/4 px-5 py-3 text-[15px] font-semibold transition-transform duration-150 hover:-translate-y-px hover:bg-white/8"
            >
              <a href={GITHUB_URL}>
                <Star aria-hidden />
                Star on GitHub
              </a>
            </Button>
          </div>
          <p className="mt-5 font-mono text-[12.5px] text-faint">
            $ <span className="text-muted">requires Android adb · auto-updates via Sparkle · {APP_VERSION}</span>
          </p>
        </div>

        <Reveal>
          <PaletteDemo />
        </Reveal>
      </div>
    </header>
  )
}
