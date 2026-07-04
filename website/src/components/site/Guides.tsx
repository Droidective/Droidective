import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { guides } from "@/lib/content"

export function Guides() {
  return (
    <section id="for-you" className="mx-auto max-w-[1120px] px-6 py-26 max-[620px]:py-18">
      <SectionHead center eyebrow="deep dives" title="Built for the way you work.">
        Droidective fits a few different workflows. Here's the guide for yours.
      </SectionHead>
      <div className="grid grid-cols-3 gap-4 max-[940px]:grid-cols-2 max-[620px]:grid-cols-1">
        {guides.map((guide, i) => (
          <Reveal key={guide.title} delay={Math.min(i % 3, 2) * 80}>
            <a href={guide.href} className="group block h-full">
              <div className="flex h-full min-w-0 flex-col rounded-2xl border border-border bg-linear-to-b from-white/2 to-white/0 p-6 pb-5.5 transition-[transform,border-color] duration-150 group-hover:-translate-y-[3px] group-hover:border-green/30 motion-reduce:group-hover:translate-y-0">
                <div className="mb-4.25 grid size-11 place-items-center rounded-xl border border-green/16 bg-green/8 text-green">
                  <guide.icon className="size-5.75" aria-hidden />
                </div>
                <h3 className="mb-2 text-[17px] font-semibold tracking-[-0.01em]">{guide.title}</h3>
                <p className="mb-4 text-[14.5px] text-muted">{guide.body}</p>
                <span className="mt-auto pt-1.5 font-mono text-[12.5px] font-medium text-green transition-colors duration-150 group-hover:text-green-bright">
                  {guide.cta}
                </span>
              </div>
            </a>
          </Reveal>
        ))}
      </div>
    </section>
  )
}
