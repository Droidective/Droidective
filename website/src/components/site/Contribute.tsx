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
    <section id="contribute" className="mx-auto max-w-[1120px] px-6 py-26 max-[620px]:py-18">
      <SectionHead center eyebrow="open source" title="Built in the open. Yours to shape." />
      <div className="grid grid-cols-[1.1fr_0.9fr] gap-6 max-[940px]:grid-cols-1">
        <Reveal>
          <div className="h-full min-w-0 rounded-2xl border border-border bg-white/2 p-7.5">
            <h3 className="mb-3 text-xl font-bold tracking-[-0.01em]">Contribute</h3>
            <p className="mb-4.5 text-[15px] text-muted">
              All logic lives in a platform-agnostic Swift package (
              <code className="font-mono text-green-dim">ADBKit</code>) with 350 passing tests; the SwiftUI shell
              stays thin. Bug reports, feature ideas, and PRs are all welcome.
            </p>
            <pre className="m-0 max-w-full rounded-[10px] border border-border bg-ink-900 px-3.5 py-3 font-mono text-[12.5px] break-words whitespace-pre-wrap text-[#cdd5cb]">
              <span className="text-green">$</span> brew install xcodegen{"\n"}
              <span className="text-green">$</span> make test    <span className="text-faint"># ADBKit unit tests — no device needed</span>
              {"\n"}
              <span className="text-green">$</span> make run     <span className="text-faint"># build &amp; launch</span>
            </pre>
            <div className="mt-5 flex flex-wrap gap-3.25">
              <Button asChild className="h-auto rounded-xl px-5 py-3 text-[15px] font-bold shadow-glow hover:bg-green-bright">
                <a href={GITHUB_URL}>
                  <GithubMark />
                  View on GitHub
                </a>
              </Button>
              <Button
                asChild
                variant="outline"
                className="h-auto rounded-xl border-border-2 bg-white/4 px-5 py-3 text-[15px] font-semibold hover:bg-white/8"
              >
                <a href={`${GITHUB_URL}/issues/new/choose`}>Open an issue</a>
              </Button>
            </div>
          </div>
        </Reveal>
        <Reveal delay={80}>
          <div className="h-full min-w-0 rounded-2xl border border-border bg-white/2 p-7.5">
            <h3 className="mb-3 text-xl font-bold tracking-[-0.01em]">On the roadmap</h3>
            <p className="mb-4.5 text-[15px] text-muted">Honest about what's next:</p>
            <ul className="m-0 list-none p-0">
              <li className="flex items-start gap-3 py-2.75 text-[14.5px] text-muted">
                <span className="mt-0.5 size-4.5 shrink-0 rounded-[5px] border border-border-2" />
                <span>
                  <b className="font-semibold text-text">Resizable Apps divider</b> — drag the list / detail split in
                  the Apps explorer.
                </span>
              </li>
              <li className="flex items-start gap-3 border-t border-border py-2.75 text-[14.5px] text-muted">
                <span className="mt-0.5 size-4.5 shrink-0 rounded-[5px] border border-border-2" />
                <span>
                  <b className="font-semibold text-text">Your idea here</b> — open an issue and let's talk.
                </span>
              </li>
            </ul>
          </div>
        </Reveal>
      </div>
    </section>
  )
}
