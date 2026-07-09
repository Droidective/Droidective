import { ReleaseTimeline } from "@/components/site/ReleaseTimeline"
import { SectionHead } from "@/components/site/SectionHead"
import { Button } from "@/components/ui/button"
import { releases } from "@/lib/content"

export function Changelog() {
  return (
    <section id="changelog" className="mx-auto max-w-[1120px] px-6 py-26 max-[620px]:py-18">
      <SectionHead center eyebrow="changelog" title="Shipped, and still moving.">
        The latest releases — automatic in-app updates since v2.1.0, and Apple-notarized builds since v2.4.0.
      </SectionHead>
      <ReleaseTimeline items={releases.slice(0, 3)} />
      <div className="mt-11 text-center">
        <Button
          asChild
          variant="outline"
          className="h-auto rounded-xl border-border-2 bg-white/4 px-5 py-3 text-[15px] font-semibold hover:bg-white/8"
        >
          <a href="/changelog/">Full changelog →</a>
        </Button>
      </div>
    </section>
  )
}
