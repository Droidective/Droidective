import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { bentoFeatures } from "@/lib/content"
import { cn } from "@/lib/utils"

export function Features() {
  return (
    <section id="features" className="mx-auto max-w-[1120px] px-6 py-26 max-[620px]:py-18">
      <SectionHead eyebrow="~/features" title="An entire adb toolkit, behind one keystroke.">
        Stop memorizing flags and juggling terminal tabs. Droidective wraps the Android Debug Bridge in a fast,
        native macOS UI — and shows you the exact command behind every action.
      </SectionHead>
      <div className="grid grid-cols-3 gap-4 max-[940px]:grid-cols-2 max-[620px]:grid-cols-1">
        {bentoFeatures.map((feature, i) => (
          <Reveal
            key={feature.title}
            delay={Math.min(i % 3, 2) * 80}
            className={cn(feature.span === "wide" && "max-[940px]:col-span-1 min-[940px]:col-span-2")}
          >
            <div className="flex h-full min-w-0 flex-col rounded-2xl border border-border bg-linear-to-b from-white/2 to-white/0 p-6 pb-5.5 transition-[transform,border-color] duration-150 hover:-translate-y-[3px] hover:border-green/30 motion-reduce:hover:translate-y-0">
              <div className="mb-4.25 grid size-11 place-items-center rounded-xl border border-green/16 bg-green/8 text-green">
                <feature.icon className="size-5.75" aria-hidden />
              </div>
              <h3 className="mb-2 text-[17px] font-semibold tracking-[-0.01em]">{feature.title}</h3>
              <p className="mb-4 flex-1 text-[14.5px] text-muted">{feature.body}</p>
              <span className="inline-block max-w-full overflow-hidden font-mono text-[11.5px] text-ellipsis whitespace-nowrap text-green-dim">
                <span className="text-faint">$ </span>
                {feature.shell}
              </span>
            </div>
          </Reveal>
        ))}
      </div>
    </section>
  )
}
