import { Apple, ArrowUpRight, Monitor } from "lucide-react"

import { Reveal } from "@/components/site/Reveal"
import { platforms } from "@/lib/content"
import { cn } from "@/lib/utils"

const marks = { macos: Apple, "windows-linux": Monitor } as const

/** Where the app runs.
 *
 *  Deliberately two unequal panels rather than two matching cards: macOS is the
 *  product and the ports are a beta, and a 50/50 grid would claim they are the
 *  same offer. The larger panel carries the download; the smaller one is honest
 *  about what is missing, because someone who installs a beta expecting the Mac
 *  app files a bug that is really a copy problem. */
export function Platforms() {
  return (
    <section id="platforms" className="relative px-6 py-24">
      <div className="mx-auto max-w-[1140px]">
        <Reveal className="mb-12 max-w-[62ch]">
          <h2 className="display text-[clamp(28px,4.2vw,46px)] leading-[1.04]">
            Built for the Mac. Now running on Windows and Linux.
          </h2>
          <p className="prose-balance mt-4 text-lg leading-relaxed text-muted">
            Every tool is one Swift package with no interface in it, which is what let the
            engine move to two more platforms without being rewritten.
          </p>
        </Reveal>

        <div className="grid grid-cols-12 gap-5 max-[900px]:grid-cols-1">
          {platforms.map((platform, index) => {
            const Mark = marks[platform.id as keyof typeof marks]
            const primary = platform.status === "stable"
            return (
              <Reveal
                key={platform.id}
                delay={index * 90}
                className={cn(primary ? "col-span-7" : "col-span-5", "max-[900px]:col-span-1")}
              >
                <div className="shell shell-hover h-full">
                  <div
                    className={cn(
                      "core flex h-full flex-col p-8 max-[620px]:p-6",
                      primary &&
                        "bg-[radial-gradient(120%_100%_at_0%_0%,rgba(105,161,6,0.09),transparent_58%)]",
                    )}
                  >
                    <div className="mb-7 flex items-center gap-3">
                      <span className="flex size-9 items-center justify-center rounded-lg border border-white/[0.07] bg-white/[0.03]">
                        <Mark className="size-4 text-muted" strokeWidth={1.5} aria-hidden />
                      </span>
                      <h3 className="text-[17px] font-medium text-text">{platform.name}</h3>
                      <span
                        className={cn(
                          "rounded-md px-2 py-0.5 font-mono text-[10.5px] tracking-wide",
                          primary
                            ? "bg-green/12 text-green"
                            : "bg-amber/12 text-amber",
                        )}
                      >
                        {platform.channel}
                      </span>
                    </div>

                    <p
                      className={cn(
                        "display mb-3 leading-[1.15]",
                        primary ? "text-[30px] max-[620px]:text-[25px]" : "text-[25px] max-[620px]:text-[22px]",
                      )}
                    >
                      {platform.headline}
                    </p>
                    <p className="prose-balance mb-7 max-w-[42ch] text-[14.5px] leading-relaxed text-muted">
                      {platform.detail}
                    </p>

                    <ul className="mb-8 grid gap-2.5 border-t border-white/[0.05] pt-6">
                      {platform.points.map((point) => (
                        <li key={point} className="flex gap-2.5 text-[13.5px] leading-snug text-faint">
                          <span
                            aria-hidden
                            className={cn(
                              "mt-[7px] h-px w-3 shrink-0",
                              primary ? "bg-green/50" : "bg-white/15",
                            )}
                          />
                          {point}
                        </li>
                      ))}
                    </ul>

                    <a
                      href={platform.href}
                      data-dl={platform.id === "macos" ? "platforms" : undefined}
                      className={cn(
                        "group/cta mt-auto inline-flex w-fit items-center gap-2 rounded-full py-2 pr-2 pl-5 text-[14px] font-medium transition-all duration-700 ease-[cubic-bezier(0.32,0.72,0,1)] active:scale-[0.98]",
                        primary
                          ? "bg-green text-ink-900 hover:bg-green-bright"
                          : "border border-white/[0.09] bg-white/[0.03] text-text hover:border-white/20 hover:bg-white/[0.06]",
                      )}
                    >
                      {platform.cta}
                      <span
                        aria-hidden
                        className={cn(
                          "flex size-6 items-center justify-center rounded-full transition-all duration-700 ease-[cubic-bezier(0.32,0.72,0,1)] group-hover/cta:scale-105",
                          primary ? "bg-ink-900/20" : "bg-white/[0.07]",
                        )}
                      >
                        <ArrowUpRight
                          className="size-3.5 transition-transform duration-700 ease-[cubic-bezier(0.32,0.72,0,1)] group-hover/cta:translate-x-px group-hover/cta:-translate-y-px"
                          strokeWidth={1.75}
                        />
                      </span>
                    </a>
                  </div>
                </div>
              </Reveal>
            )
          })}
        </div>
      </div>
    </section>
  )
}
