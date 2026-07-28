import { LazyVideo } from "@/components/site/LazyVideo"
import { Reveal } from "@/components/site/Reveal"
import { showcases, galleryShots } from "@/lib/content"
import { cn } from "@/lib/utils"

export function Screenshots() {
  return (
    <section id="screenshots" className="mx-auto max-w-[1120px] px-6 py-28 max-[620px]:py-20">
      {/* Hero demo video */}
      <Reveal className="mx-auto mb-22 max-w-245">
        <div className="overflow-hidden rounded-2xl border border-white/[0.06] bg-ink-700/50 shadow-[0_40px_100px_-30px_rgba(0,0,0,0.6)]">
          <LazyVideo
            src="/assets/demo.mp4"
            poster="/assets/demo-poster.webp"
            width={1280}
            height={810}
            label="Droidective in action — pressing ⌘T to jump between live Logcat, Device Info, the File Explorer, and the React Native hub on a connected Android emulator"
          />
        </div>
      </Reveal>

      {/* Feature showcases */}
      <div className="flex flex-col gap-24">
        {showcases.map((showcase) => (
          <Reveal key={showcase.title}>
            <div className="grid grid-cols-2 items-center gap-12 max-[940px]:grid-cols-1 max-[940px]:gap-8">
              <div className={cn("min-w-0", showcase.flip && "min-[940px]:order-2")}>
                <span className="font-mono text-[12px] font-medium tracking-[0.06em] text-green/80 uppercase">
                  <span className="mr-2 text-green-dim/60">&gt;_</span>
                  {showcase.eyebrow}
                </span>
                <h3 className="mt-3 mb-3.5 text-[24px] font-bold tracking-[-0.02em]">{showcase.title}</h3>
                <p className="mb-5 text-[15px] leading-relaxed text-muted">{showcase.body}</p>
                <ul className="m-0 list-none p-0">
                  {showcase.ticks.map((tick) => (
                    <li key={tick.lead} className="relative my-2.5 pl-6 text-[14.5px] text-muted/90">
                      <span className="absolute top-0 left-0 font-mono font-bold text-green/70">&gt;</span>
                      <b className="font-semibold text-text">{tick.lead}</b>
                      {tick.rest}
                    </li>
                  ))}
                </ul>
              </div>
              <div
                className={cn(
                  "min-w-0 overflow-hidden rounded-[14px] border border-white/[0.06] shadow-[0_30px_70px_-28px_rgba(0,0,0,0.6)]",
                  showcase.flip && "min-[940px]:order-1",
                )}
              >
                {showcase.video ? (
                  <LazyVideo
                    src={showcase.video}
                    poster={showcase.image}
                    width={1600}
                    height={1012}
                    label={showcase.alt}
                  />
                ) : (
                  <img
                    src={showcase.image}
                    alt={showcase.alt}
                    width={1600}
                    height={1012}
                    loading="lazy"
                    decoding="async"
                    className="block h-auto w-full"
                  />
                )}
              </div>
            </div>
          </Reveal>
        ))}
      </div>

      {/* Gallery */}
      <Reveal className="mt-24 grid grid-cols-[repeat(auto-fit,minmax(260px,1fr))] gap-5">
        {galleryShots.map((shot) => (
          <figure key={shot.title} className="m-0">
            <div className="overflow-hidden rounded-[14px] border border-white/[0.06] shadow-[0_20px_50px_-20px_rgba(0,0,0,0.5)] transition-transform duration-200 hover:-translate-y-0.5">
              <img src={shot.image} alt={shot.alt} width={1600} height={1000} loading="lazy" decoding="async" className="block aspect-[16/10] w-full object-cover object-top" />
            </div>
            <figcaption className="mt-3.5 text-sm leading-normal text-muted/90">
              <b className="block text-[14.5px] font-semibold text-text">{shot.title}</b>
              {shot.caption}
            </figcaption>
          </figure>
        ))}
      </Reveal>
    </section>
  )
}
