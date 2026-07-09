import { Reveal } from "@/components/site/Reveal"
import { releases } from "@/lib/content"
import { cn } from "@/lib/utils"

/** The vertical release timeline — the landing section shows the latest few,
 *  the /changelog/ page shows the full history. */
export function ReleaseTimeline({ items }: { items: typeof releases }) {
  return (
    <Reveal className="relative mx-auto max-w-190 pl-7.5 before:absolute before:top-2 before:bottom-2 before:left-1.25 before:w-px before:bg-border-2">
      {items.map((release) => (
        <div key={release.version} className="relative pb-9 last:pb-0">
          <span
            className={cn(
              "absolute top-1.5 -left-[29px] size-2.75 rounded-full border-2",
              release.latest
                ? "border-green bg-green shadow-[0_0_12px_rgba(155,224,33,0.3)]"
                : "border-green-dim bg-ink-850",
            )}
          />
          <div className="mb-1.75 flex flex-wrap items-baseline gap-3">
            <span className="font-mono text-[15px] font-bold text-green">{release.version}</span>
            {release.latest && (
              <span className="rounded-full bg-green px-2 py-px font-mono text-[11px] font-bold text-ink-900">
                latest
              </span>
            )}
            <span className="ml-auto font-mono text-xs text-faint max-[620px]:ml-0 max-[620px]:w-full">
              {release.date}
            </span>
          </div>
          <p
            className="m-0 text-[14.5px] text-muted [&_b]:font-semibold [&_b]:text-text [&_code]:font-mono"
            dangerouslySetInnerHTML={{ __html: release.html }}
          />
        </div>
      ))}
    </Reveal>
  )
}
