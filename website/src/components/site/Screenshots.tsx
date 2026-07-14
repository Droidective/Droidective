import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"
import { galleryShots, showcases } from "@/lib/content"
import { cn } from "@/lib/utils"

export function Screenshots() {
  // Under reduced motion the videos sit on their posters with controls
  // instead of autoplaying.
  const reducedMotion = usePrefersReducedMotion()

  return (
    <section id="screenshots" className="mx-auto max-w-[1120px] px-6 py-26 max-[620px]:py-18">
      <SectionHead center eyebrow="see it in action" title="Real screens. Real device.">
        Every shot below is the actual app driving a live Android emulator — no mockups.
      </SectionHead>

      <Reveal className="mx-auto mb-21 max-w-245 overflow-hidden rounded-2xl border border-border-2 bg-ink-700 shadow-[0_40px_100px_-30px_rgba(0,0,0,0.7)]">
        <video
          className="block h-auto w-full"
          autoPlay={!reducedMotion}
          controls={reducedMotion}
          muted
          loop
          playsInline
          preload="metadata"
          poster="/assets/demo-poster.webp"
          width={1280}
          height={810}
          aria-label="Droidective in action — pressing ⌘T to jump between live Logcat, Device Info, the File Explorer, and the React Native hub on a connected Android emulator"
        >
          <source src="/assets/demo.mp4" type="video/mp4" />
        </video>
      </Reveal>

      <div className="flex flex-col gap-22">
        {showcases.map((showcase) => (
          <Reveal key={showcase.title}>
            <div className="grid grid-cols-2 items-center gap-11 max-[940px]:grid-cols-1 max-[940px]:gap-7">
              <div className={cn("min-w-0", showcase.flip && "min-[940px]:order-2")}>
                <span className="font-mono text-[12.5px] font-medium tracking-[0.04em] text-green">
                  <span className="mr-2 text-green-dim">&gt;_</span>
                  {showcase.eyebrow}
                </span>
                <h3 className="mt-3 mb-3.5 text-[25px] font-bold tracking-[-0.02em]">{showcase.title}</h3>
                <p className="mb-4.5 text-base text-muted">{showcase.body}</p>
                <ul className="m-0 list-none p-0">
                  {showcase.ticks.map((tick) => (
                    <li key={tick.lead} className="relative my-2.5 pl-6.5 text-[15px] text-muted">
                      <span className="absolute top-0 left-0 font-mono font-bold text-green">&gt;</span>
                      <b className="font-semibold text-text">{tick.lead}</b>
                      {tick.rest}
                    </li>
                  ))}
                </ul>
              </div>
              <div
                className={cn(
                  "min-w-0 overflow-hidden rounded-[14px] border border-border-2 shadow-[0_30px_70px_-28px_rgba(0,0,0,0.7)]",
                  showcase.flip && "min-[940px]:order-1",
                )}
              >
                {showcase.video ? (
                  <video
                    className="block h-auto w-full"
                    autoPlay={!reducedMotion}
                    controls={reducedMotion}
                    muted
                    loop
                    playsInline
                    preload="metadata"
                    poster={showcase.image}
                    width={1600}
                    height={1012}
                    aria-label={showcase.alt}
                  >
                    <source src={showcase.video} type="video/mp4" />
                  </video>
                ) : (
                  <img
                    src={showcase.image}
                    alt={showcase.alt}
                    width={1600}
                    height={1012}
                    loading="lazy"
                    className="block h-auto w-full"
                  />
                )}
              </div>
            </div>
          </Reveal>
        ))}
      </div>

      <Reveal className="mt-22 grid grid-cols-[repeat(auto-fit,minmax(260px,1fr))] gap-5">
        {galleryShots.map((shot) => (
          <figure key={shot.title} className="m-0">
            <div className="overflow-hidden rounded-[14px] border border-border-2 shadow-[0_30px_70px_-28px_rgba(0,0,0,0.7)]">
              <img src={shot.image} alt={shot.alt} width={1600} height={1000} loading="lazy" className="block aspect-[16/10] w-full object-cover object-top" />
            </div>
            <figcaption className="mt-3.5 text-sm leading-normal text-muted">
              <b className="block text-[15px] font-semibold text-text">{shot.title}</b>
              {shot.caption}
            </figcaption>
          </figure>
        ))}
      </Reveal>
    </section>
  )
}
