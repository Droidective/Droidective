import { MagicCard } from "@/components/MagicCard"
import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { Button } from "@/components/ui/button"
import { GITHUB_URL } from "@/lib/content"

function GithubMark() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden className="size-4">
      <path d="M12 1.5A10.5 10.5 0 0 0 8.7 22c.5.1.7-.2.7-.5v-1.8c-2.9.6-3.5-1.4-3.5-1.4-.5-1.2-1.2-1.5-1.2-1.5-.9-.6.1-.6.1-.6 1 .1 1.6 1 1.6 1 .9 1.6 2.4 1.1 3 .9.1-.7.4-1.1.6-1.4-2.3-.3-4.7-1.2-4.7-5.1 0-1.1.4-2 1-2.7-.1-.3-.5-1.3.1-2.7 0 0 .8-.3 2.7 1a9.4 9.4 0 0 1 5 0c1.9-1.3 2.7-1 2.7-1 .6 1.4.2 2.4.1 2.7.6.7 1 1.6 1 2.7 0 3.9-2.4 4.8-4.7 5.1.4.3.7 1 .7 2v2.9c0 .3.2.6.7.5A10.5 10.5 0 0 0 12 1.5" />
    </svg>
  )
}

export function Contribute() {
  return (
    <section id="contribute" className="section-contained mx-auto max-w-[1120px] px-6 py-28 max-[620px]:py-20">
      <SectionHead center title="Built in the open. Yours to shape." />
      <div className="grid grid-cols-[1.1fr_0.9fr] gap-4 max-[940px]:grid-cols-1">
        <Reveal>
          <MagicCard className="h-full">
            <div className="flex h-full min-w-0 flex-col p-7">
              <h3 className="mb-3 text-xl font-bold tracking-[-0.01em]">Contribute</h3>
              <p className="mb-5 text-[14.5px] leading-relaxed text-muted/90">
                All logic lives in a platform-agnostic Swift package (
                <code className="font-mono text-green-dim">ADBKit</code>) with 350 passing tests; the SwiftUI shell
                stays thin. Bug reports, feature ideas, and PRs are all welcome.
              </p>
              <pre className="m-0 max-w-full rounded-[10px] border border-white/[0.06] bg-ink-900/60 px-3.5 py-3 font-mono text-[12px] break-words whitespace-pre-wrap text-[#cdd5cb]">
                <span className="text-green">$</span> brew install xcodegen{"\n"}
                <span className="text-green">$</span> make test    <span className="text-faint/60"># ADBKit unit tests, no device needed</span>
                {"\n"}
                <span className="text-green">$</span> make run     <span className="text-faint/60"># build &amp; launch</span>
              </pre>
              <div className="mt-5 flex flex-wrap gap-3">
                <Button asChild className="h-auto rounded-xl px-5 py-2.5 text-[14px] font-bold shadow-glow transition-all duration-200 hover:-translate-y-px hover:bg-green-bright">
                  <a href={GITHUB_URL}>
                    <GithubMark />
                    View on GitHub
                  </a>
                </Button>
                <Button
                  asChild
                  variant="outline"
                  className="h-auto rounded-xl border-white/[0.08] bg-white/[0.03] px-5 py-2.5 text-[14px] font-semibold hover:bg-white/[0.06]"
                >
                  <a href={`${GITHUB_URL}/issues/new/choose`}>Open an issue</a>
                </Button>
              </div>
            </div>
          </MagicCard>
        </Reveal>
        <Reveal delay={60}>
          <MagicCard className="h-full">
            <div className="flex h-full min-w-0 flex-col p-7">
              <h3 className="mb-3 text-xl font-bold tracking-[-0.01em]">On the roadmap</h3>
              <p className="mb-5 text-[14.5px] leading-relaxed text-muted/90">Honest about what's next:</p>
              <ul className="m-0 list-none p-0">
                <li className="flex items-start gap-3 py-3 text-[14px] text-muted/90">
                  <span className="mt-0.5 size-4 shrink-0 rounded-[5px] border border-white/[0.08]" />
                  <span>
                    <b className="font-semibold text-text">Resizable Apps divider</b>: drag the list / detail split in
                    the Apps explorer.
                  </span>
                </li>
                <li className="flex items-start gap-3 border-t border-white/[0.04] py-3 text-[14px] text-muted/90">
                  <span className="mt-0.5 size-4 shrink-0 rounded-[5px] border border-white/[0.08]" />
                  <span>
                    <b className="font-semibold text-text">Your idea here</b>: open an issue and let's talk.
                  </span>
                </li>
              </ul>
            </div>
          </MagicCard>
        </Reveal>
      </div>
    </section>
  )
}
