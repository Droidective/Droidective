import { MagicCard } from "@/components/MagicCard"
import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { bentoFeatures } from "@/lib/content"
import { cn } from "@/lib/utils"

export function Features() {
  return (
    <section id="features" className="relative mx-auto max-w-[1120px] px-6 py-28 max-[620px]:py-20">
      <SectionHead eyebrow="~/features" title="An entire adb toolkit, behind one keystroke.">
        Stop memorizing flags and juggling terminal tabs. Droidective wraps the Android Debug Bridge in a fast,
        native macOS UI — and shows you the exact command behind every action.
      </SectionHead>
      <div className="grid grid-cols-3 gap-4 max-[940px]:grid-cols-2 max-[620px]:grid-cols-1">
        {bentoFeatures.map((feature, i) => (
          <Reveal
            key={feature.title}
            delay={Math.min(i % 3, 2) * 60}
            className={cn(feature.span === "wide" && "max-[940px]:col-span-1 min-[940px]:col-span-2")}
          >
            <MagicCard className="h-full">
              <div className="flex h-full min-w-0 flex-col p-6 pb-5.5">
                <div className="mb-4 grid size-10 place-items-center rounded-xl border border-green/12 bg-green/[0.06] text-green">
                  <feature.icon className="size-5" aria-hidden />
                </div>
                <h3 className="mb-2 text-[16px] font-semibold tracking-[-0.01em]">{feature.title}</h3>
                <p className="mb-4 flex-1 text-[14px] leading-relaxed text-muted/90">{feature.body}</p>
                <span className="inline-block max-w-full overflow-hidden font-mono text-[11px] text-ellipsis whitespace-nowrap text-green-dim/80">
                  <span className="text-faint/60">$ </span>
                  {feature.shell}
                </span>
              </div>
            </MagicCard>
          </Reveal>
        ))}
      </div>
    </section>
  )
}
