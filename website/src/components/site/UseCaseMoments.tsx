import { Reveal } from "@/components/site/Reveal"
import { useCaseMoments } from "@/lib/content"

/** Human-framed moments — the sentence a developer actually says out loud,
 *  then the answer. Deliberately compact: no images, no big cards. */
export function UseCaseMoments() {
  return (
    <section className="mx-auto max-w-[1120px] px-6 py-24 max-[620px]:py-16">
      <Reveal className="mb-12 max-w-[52ch]">
        <span className="font-mono text-[12px] font-medium tracking-[0.06em] text-green/80 uppercase">
          <span className="mr-2 text-green-dim/60">&gt;_</span>
          moments
        </span>
        <h2 className="mt-4 text-[clamp(26px,3.6vw,38px)] leading-[1.08] font-extrabold tracking-[-0.03em]">
          Built for the moments that slow you down.
        </h2>
      </Reveal>

      <div className="grid grid-cols-2 gap-x-10 gap-y-1 max-[620px]:grid-cols-1">
        {useCaseMoments.map((m) => (
          <Reveal key={m.quote}>
            <a
              href={m.href}
              className="group flex items-start gap-4 border-t border-white/[0.05] py-5 transition-colors duration-200 hover:border-green/20"
            >
              <span className="min-w-0 flex-1">
                <span className="block text-[16px] font-semibold tracking-[-0.01em] transition-colors duration-200 group-hover:text-green">
                  {m.quote}
                </span>
                <span className="mt-1.5 block text-[13.5px] leading-relaxed text-muted/80">{m.answer}</span>
              </span>
              <span
                aria-hidden
                className="mt-1 shrink-0 font-mono text-[13px] text-faint/40 transition-all duration-200 group-hover:translate-x-0.5 group-hover:text-green"
              >
                →
              </span>
            </a>
          </Reveal>
        ))}
      </div>
    </section>
  )
}
