import { useState } from "react"

import { Plus } from "lucide-react"

import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { featureGroups } from "@/lib/content"
import { cn } from "@/lib/utils"

/** Grouped, collapsed-by-default so the full 59-tool surface is available
 *  without dumping 59 cards on the page. */
export function FeatureExplorer() {
  const [open, setOpen] = useState<string | null>(featureGroups[0]!.name)

  return (
    <section id="features" className="mx-auto max-w-[1120px] px-6 py-32 max-[620px]:py-20">
      <SectionHead center eyebrow="every tool" title="Everything you need to debug faster.">
        All 59 tools, grouped by what they're for. Open a group to see what's inside.
      </SectionHead>

      <Reveal className="mx-auto max-w-[840px]">
        <div className="overflow-hidden rounded-2xl border border-white/[0.06]">
          {featureGroups.map((group) => {
            const isOpen = open === group.name
            return (
              <div key={group.name} className="border-b border-white/[0.05] last:border-0">
                <button
                  type="button"
                  aria-expanded={isOpen}
                  onClick={() => setOpen(isOpen ? null : group.name)}
                  className="flex w-full cursor-pointer items-center gap-4 px-5 py-4.5 text-left transition-colors duration-150 hover:bg-white/[0.02]"
                >
                  <span
                    className={cn(
                      "grid size-9 shrink-0 place-items-center rounded-xl border transition-colors duration-200",
                      isOpen
                        ? "border-green/20 bg-green/[0.08] text-green"
                        : "border-white/[0.06] bg-white/[0.02] text-muted/70",
                    )}
                  >
                    <group.icon className="size-4.5" aria-hidden />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-[15.5px] font-semibold tracking-[-0.01em]">{group.name}</span>
                    <span className="font-mono text-[11px] text-faint/60">{group.count}</span>
                  </span>
                  <Plus
                    className={cn(
                      "size-4 shrink-0 text-muted/50 transition-transform duration-200",
                      isOpen && "rotate-45 text-green",
                    )}
                    aria-hidden
                  />
                </button>
                {isOpen && (
                  <ul className="m-0 grid grid-cols-3 gap-x-6 gap-y-2 px-5 pt-1 pb-5 pl-[72px] motion-safe:animate-[fadeUp_.3s_ease-out] max-[940px]:grid-cols-2 max-[620px]:grid-cols-1 max-[620px]:pl-5">
                    {group.items.map((item) => (
                      <li key={item} className="flex items-baseline gap-2 text-[13.5px] text-muted/85">
                        <span aria-hidden className="font-mono text-[10px] text-green/50">
                          ▸
                        </span>
                        {item}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )
          })}
        </div>
      </Reveal>
    </section>
  )
}
