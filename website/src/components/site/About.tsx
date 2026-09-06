import CountUp from "@/components/CountUp"
import { MagicCard } from "@/components/MagicCard"
import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { Button } from "@/components/ui/button"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"
import { GITHUB_URL, LINKEDIN_URL } from "@/lib/content"

function LinkedInMark() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden className="size-4">
      <path d="M20.45 20.45h-3.55v-5.57c0-1.33-.03-3.04-1.85-3.04-1.86 0-2.14 1.45-2.14 2.94v5.67H9.35V9h3.41v1.56h.05c.47-.9 1.63-1.85 3.36-1.85 3.6 0 4.27 2.37 4.27 5.45zM5.34 7.43a2.06 2.06 0 1 1 0-4.12 2.06 2.06 0 0 1 0 4.12M7.12 20.45H3.55V9h3.57zM22.22 0H1.77C.79 0 0 .77 0 1.72v20.55C0 23.23.79 24 1.77 24h20.45c.98 0 1.78-.77 1.78-1.73V1.72C24 .77 23.2 0 22.22 0" />
    </svg>
  )
}

function GithubMark() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden className="size-4">
      <path d="M12 1.5A10.5 10.5 0 0 0 8.7 22c.5.1.7-.2.7-.5v-1.8c-2.9.6-3.5-1.4-3.5-1.4-.5-1.2-1.2-1.5-1.2-1.5-.9-.6.1-.6.1-.6 1 .1 1.6 1 1.6 1 .9 1.6 2.4 1.1 3 .9.1-.7.4-1.1.6-1.4-2.3-.3-4.7-1.2-4.7-5.1 0-1.1.4-2 1-2.7-.1-.3-.5-1.3.1-2.7 0 0 .8-.3 2.7 1a9.4 9.4 0 0 1 5 0c1.9-1.3 2.7-1 2.7-1 .6 1.4.2 2.4.1 2.7.6.7 1 1.6 1 2.7 0 3.9-2.4 4.8-4.7 5.1.4.3.7 1 .7 2v2.9c0 .3.2.6.7.5A10.5 10.5 0 0 0 12 1.5" />
    </svg>
  )
}

const highlights = [
  { value: 4, suffix: "+", label: "years building mobile apps" },
  { value: 1, suffix: "M+", label: "downloads on a shipped app" },
  { value: 40, suffix: "+", label: "releases managed end-to-end" },
]

const stack = ["React Native", "Android", "iOS", "Swift", "TypeScript", "Mobile Security"]

export function About() {
  const reducedMotion = usePrefersReducedMotion()

  return (
    <section id="about" className="section-contained mx-auto max-w-[1120px] px-6 pb-28 max-[620px]:pb-20">
      <SectionHead center title="About me." />
      <div className="grid grid-cols-[1.1fr_0.9fr] gap-4 max-[940px]:grid-cols-1">
        <Reveal>
          <MagicCard className="h-full">
            <div className="flex h-full min-w-0 flex-col p-7">
              <p className="mb-1 text-xl font-bold tracking-[-0.01em]">Rohindh R</p>
              <p className="mb-5 font-mono text-[12px] text-green-dim/80">
                mobile engineer · React Native / Android / iOS / Swift
              </p>
              <p className="mb-4 text-[14.5px] leading-relaxed text-muted/90">
                I build and ship production mobile apps for a living, taking them from first commit through app-store
                review, over-the-air updates, and the crash reports that follow. Along the way I developed a particular
                interest in mobile security: hardening apps, and understanding how they break.
              </p>
              <p className="mb-4 text-[14.5px] leading-relaxed text-muted/90">
                Droidective grew out of my own daily debugging loop: the adb incantations, the log tails, the device
                state I kept faking by hand. I wanted all of it one keystroke away, so I built it.
              </p>
              <p className="mb-6 text-[14.5px] leading-relaxed text-muted/90">
                It's free and open source by choice: everything I've built in my career stands on open-source software,
                and this project is my way of giving back to that community.
              </p>
              <div className="flex flex-wrap gap-3">
                <Button
                  asChild
                  variant="outline"
                  className="h-auto rounded-xl border-white/[0.08] bg-white/[0.03] px-5 py-2.5 text-[14px] font-semibold hover:bg-white/[0.06]"
                >
                  <a href={LINKEDIN_URL}>
                    <LinkedInMark />
                    Connect on LinkedIn
                  </a>
                </Button>
                <Button
                  asChild
                  variant="outline"
                  className="h-auto rounded-xl border-white/[0.08] bg-white/[0.03] px-5 py-2.5 text-[14px] font-semibold hover:bg-white/[0.06]"
                >
                  <a href={GITHUB_URL}>
                    <GithubMark />
                    Follow the project
                  </a>
                </Button>
              </div>
            </div>
          </MagicCard>
        </Reveal>
        <Reveal delay={60}>
          <MagicCard className="h-full">
            <div className="flex h-full min-w-0 flex-col p-7">
              <ul className="m-0 list-none p-0">
                {highlights.map((h) => (
                  <li key={h.label} className="flex items-baseline gap-3.5 border-b border-white/[0.04] py-3.5 first:pt-0">
                    <span className="font-mono text-[26px] font-bold tracking-[-0.02em] text-green">
                      {reducedMotion ? h.value : <CountUp to={h.value} duration={1.2} />}
                      {h.suffix}
                    </span>
                    <span className="text-[13.5px] text-muted/80">{h.label}</span>
                  </li>
                ))}
              </ul>
              <div className="mt-auto pt-5">
                <p className="mb-2.5 font-mono text-[11px] text-faint/60">$ tools of the trade</p>
                <div className="flex flex-wrap gap-2">
                  {stack.map((item) => (
                    <span
                      key={item}
                      className="rounded-full border border-white/[0.06] bg-white/[0.02] px-3 py-1 font-mono text-[11.5px] text-muted/70"
                    >
                      {item}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          </MagicCard>
        </Reveal>
      </div>
    </section>
  )
}
