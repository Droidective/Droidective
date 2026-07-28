import { MagicCard } from "@/components/MagicCard"
import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { guides } from "@/lib/content"

export function Guides() {
  return (
    <section className="mx-auto max-w-[1120px] px-6 py-28 max-[620px]:py-20">
      <SectionHead center eyebrow="deep dives" title="Built for the way you work.">
        Droidective fits a few different workflows. Here's the guide for yours.
      </SectionHead>
      <div className="grid grid-cols-3 gap-4 max-[940px]:grid-cols-2 max-[620px]:grid-cols-1">
        {guides.map((guide, i) => (
          <Reveal key={guide.title} delay={Math.min(i % 3, 2) * 60}>
            <a href={guide.href} className="group block h-full">
              <MagicCard className="h-full">
                <div className="flex h-full min-w-0 flex-col p-6 pb-5.5">
                  <div className="mb-4 grid size-10 place-items-center rounded-xl border border-green/12 bg-green/[0.06] text-green">
                    <guide.icon className="size-5" aria-hidden />
                  </div>
                  <h3 className="mb-2 text-[16px] font-semibold tracking-[-0.01em]">{guide.title}</h3>
                  <p className="mb-4 flex-1 text-[14px] leading-relaxed text-muted/90">{guide.body}</p>
                  <span className="mt-auto pt-1.5 font-mono text-[12px] font-medium text-green/70 transition-colors duration-200 group-hover:text-green">
                    {guide.cta}
                  </span>
                </div>
              </MagicCard>
            </a>
          </Reveal>
        ))}
      </div>
    </section>
  )
}
