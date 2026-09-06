import { ReleaseTimeline } from "@/components/site/ReleaseTimeline"
import { SectionHead } from "@/components/site/SectionHead"
import { Button } from "@/components/ui/button"
import { releases } from "@/lib/content"

export function Changelog() {
  return (
    <section id="changelog" className="section-contained-tall mx-auto max-w-[1120px] px-6 py-28 max-[620px]:py-20">
      <SectionHead center title="Shipped, and still moving.">
        The latest releases. Automatic in-app updates since v2.1.0, and Apple-notarized builds since v2.4.0.
      </SectionHead>
      <ReleaseTimeline items={releases.slice(0, 3)} />
      <div className="mt-12 text-center">
        <Button
          asChild
          variant="outline"
          className="h-auto rounded-xl border-white/[0.08] bg-white/[0.03] px-5 py-3 text-[14.5px] font-semibold transition-all duration-200 hover:border-white/[0.14] hover:bg-white/[0.06]"
        >
          <a href="/changelog/">Full changelog →</a>
        </Button>
      </div>
    </section>
  )
}
