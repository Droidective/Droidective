import { Footer } from "@/components/site/Footer"
import { ReleaseTimeline } from "@/components/site/ReleaseTimeline"
import { SectionHead } from "@/components/site/SectionHead"
import { Button } from "@/components/ui/button"
import { RELEASES_URL, releases } from "@/lib/content"

/** The /changelog/ page: the full release history (the landing page's
 *  changelog section shows only the latest few). */
export function ChangelogPage() {
  return (
    <>
      <header className="border-b border-border px-6 py-4">
        <div className="mx-auto flex max-w-[1120px] items-center justify-between gap-4">
          <a href="/" className="flex items-center gap-2.75 text-base font-bold tracking-[-0.01em]">
            <img src="/assets/icon-light-64.png" alt="" width={26} height={26} className="rounded-md" />
            Droidective
          </a>
          <a
            href="/"
            className="font-mono text-[13px] text-muted transition-colors duration-150 hover:text-green"
          >
            ← back to droidective.com
          </a>
        </div>
      </header>
      <main className="mx-auto max-w-[1120px] px-6 py-20 max-[620px]:py-12">
        <SectionHead center eyebrow="changelog" title="Every release.">
          {releases.length} releases since the first public build — automatic in-app updates since v2.1.0, and
          Apple-notarized builds since v2.4.0.
        </SectionHead>
        <ReleaseTimeline items={releases} />
        <div className="mt-11 text-center">
          <Button
            asChild
            variant="outline"
            className="h-auto rounded-xl border-border-2 bg-white/4 px-5 py-3 text-[15px] font-semibold hover:bg-white/8"
          >
            <a href={RELEASES_URL}>All releases on GitHub →</a>
          </Button>
        </div>
      </main>
      <Footer />
    </>
  )
}
