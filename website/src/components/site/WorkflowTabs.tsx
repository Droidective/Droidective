import { useState } from "react"

import { Check } from "lucide-react"

import { LazyVideo } from "@/components/site/LazyVideo"
import { ApkMock, McpFlow } from "@/components/site/ProductMocks"
import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { workflows } from "@/lib/content"
import { cn } from "@/lib/utils"

/** The homepage's primary feature story: six workflows, one visual each.
 *  This replaces the old vertical screenshot gallery — a visitor sees one
 *  purposeful visual at a time instead of sixteen in a row. */
export function WorkflowTabs() {
  const [active, setActive] = useState(0)
  const wf = workflows[active]!

  return (
    <section id="workflows" className="mx-auto max-w-[1120px] px-6 pt-20 pb-32 max-[620px]:pt-14 max-[620px]:pb-20">
      <SectionHead eyebrow="workflows" title="Built for how you debug.">
        Not a pile of features. Six workflows that cover the whole loop between writing code and
        understanding what your app actually did.
      </SectionHead>

      {/* Segmented tab control. Scrolls horizontally on mobile rather than wrapping. */}
      <Reveal className="mb-10">
        <div className="-mx-6 overflow-x-auto px-6 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          <div className="flex w-max min-w-full gap-1 rounded-2xl border border-white/[0.06] bg-white/[0.02] p-1.5">
            {workflows.map((w, i) => (
              <button
                key={w.id}
                type="button"
                onClick={() => setActive(i)}
                aria-pressed={i === active}
                className={cn(
                  "flex flex-1 items-center justify-center gap-2 rounded-xl px-4 py-2.5 font-mono text-[12.5px] font-medium whitespace-nowrap transition-all duration-200",
                  i === active
                    ? "bg-green/12 text-green shadow-[inset_0_0_0_1px_rgba(105,161,6,0.2)]"
                    : "text-muted/70 hover:bg-white/[0.04] hover:text-text",
                )}
              >
                <w.icon className="size-4 shrink-0" aria-hidden />
                {w.tab}
              </button>
            ))}
          </div>
        </div>
      </Reveal>

      {/* Panel — keyed so the crossfade replays on every tab change. */}
      <div key={wf.id} className="grid grid-cols-[0.85fr_1.15fr] items-center gap-12 max-[940px]:grid-cols-1 max-[940px]:gap-8">
        <div className="min-w-0 motion-safe:animate-[fadeUp_.45s_ease-out]">
          <div className="mb-4 flex items-baseline gap-2.5">
            <span className="font-mono text-[28px] font-bold leading-none text-green/25">{wf.num}</span>
            <span className="font-mono text-[11px] tracking-[0.08em] text-green/70 uppercase">{wf.tab}</span>
          </div>
          <h3 className="mb-4 text-[26px] leading-[1.15] font-bold tracking-[-0.025em] max-[620px]:text-[22px]">
            {wf.title}
          </h3>
          <p className="mb-6 text-[15px] leading-relaxed text-muted">{wf.blurb}</p>
          <ul className="m-0 grid grid-cols-2 gap-x-5 gap-y-2.5 p-0 max-[620px]:grid-cols-1">
            {wf.features.map((f) => (
              <li key={f} className="flex items-center gap-2 text-[13.5px] text-muted/90">
                <Check className="size-3.5 shrink-0 text-green/70" aria-hidden />
                {f}
              </li>
            ))}
          </ul>
        </div>

        <div className="min-w-0 motion-safe:animate-[fadeUp_.55s_ease-out]">
          {wf.mock === "apk" ? (
            <ApkMock />
          ) : wf.mock === "mcp" ? (
            <McpFlow />
          ) : wf.video ? (
            <div className="overflow-hidden rounded-[14px] border border-white/[0.08] shadow-[0_30px_70px_-28px_rgba(0,0,0,0.6)]">
              <LazyVideo src={wf.video} poster={wf.image!} width={1600} height={1012} label={wf.alt!} />
            </div>
          ) : (
            <div className="overflow-hidden rounded-[14px] border border-white/[0.08] shadow-[0_30px_70px_-28px_rgba(0,0,0,0.6)]">
              <img
                src={wf.image}
                alt={wf.alt}
                width={1600}
                height={1012}
                loading="lazy"
                decoding="async"
                className="block h-auto w-full"
              />
            </div>
          )}
        </div>
      </div>
    </section>
  )
}
