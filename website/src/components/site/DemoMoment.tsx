import { LazyVideo } from "@/components/site/LazyVideo"
import { Reveal } from "@/components/site/Reveal"

/** One immersive video instead of a screenshot gallery. Motion earns its place
 *  here: the point is how fast ⌘T moves between tools, which a still can't show. */
export function DemoMoment() {
  return (
    <section id="in-action" className="relative overflow-hidden py-32 max-[620px]:py-20">
      <div
        aria-hidden
        className="pointer-events-none absolute top-1/4 left-1/2 h-[400px] w-[1000px] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(105,161,6,0.05),transparent_70%)] blur-3xl"
      />

      <div className="relative mx-auto max-w-[1120px] px-6">
        <Reveal className="mx-auto mb-12 max-w-[54ch] text-center">
          <span className="font-mono text-[12px] font-medium tracking-[0.06em] text-green/80 uppercase">
            <span className="mr-2 text-green-dim/60">&gt;_</span>
            in action
          </span>
          <h2 className="mt-4 mb-4 text-[clamp(28px,4.2vw,46px)] leading-[1.04] font-extrabold tracking-[-0.035em]">
            Watch it work.
          </h2>
          <p className="text-lg leading-relaxed text-muted">
            The real app on a live Android device — logcat, device info, files, and the React Native hub,
            all without leaving the window.
          </p>
        </Reveal>

        <Reveal className="mx-auto max-w-[960px]">
          <div className="overflow-hidden rounded-2xl border border-white/[0.08] bg-ink-700/40 shadow-[0_50px_120px_-35px_rgba(0,0,0,0.7)]">
            <LazyVideo
              src="/assets/demo.mp4"
              poster="/assets/demo-poster.webp"
              width={1280}
              height={810}
              label="Droidective in action — pressing ⌘T to jump between live Logcat, Device Info, the File Explorer, and the React Native hub on a connected Android emulator"
            />
          </div>
        </Reveal>
      </div>
    </section>
  )
}
