import { polyline, series } from "@/lib/performance"

/**
 * One metric over time.
 *
 * Hand-drawn SVG rather than a chart library: three lines do not justify the
 * dependency, and a `viewBox` scales without this knowing its own size. The
 * scaling and the point list are `lib/performance.ts`, so what is left here is
 * drawing.
 */
export function PerfChart<Sample extends { elapsed: number }>({
  title,
  value,
  samples,
  pick,
  max,
  tone = "accent",
}: {
  title: string
  /** The headline figure, already formatted. */
  value: string
  /**
   * Anything with an elapsed clock. Generic rather than tied to a performance
   * sample so Memory Usage draws its Total-PSS line with the same component —
   * the Mac uses one `Chart` for both, and two sparklines that disagreed about
   * their axis would be the difference someone notices.
   */
  samples: readonly Sample[]
  pick: (sample: Sample) => number | null
  /** The top of the y axis, in the metric's own units. */
  max: number
  tone?: "accent" | "warn" | "danger"
}) {
  const stroke = {
    accent: "var(--color-accent)",
    warn: "var(--color-warn)",
    danger: "var(--color-danger)",
  }[tone]
  const points = polyline(series(samples, pick, max))
  const span = samples.at(-1)?.elapsed ?? 0

  return (
    <section className="flex min-w-0 flex-col gap-1 rounded-lg border border-border-subtle bg-bg-surface p-3">
      <header className="flex items-baseline justify-between gap-2">
        <h3 className="text-[10.5px] uppercase tracking-[0.06em] text-text-tertiary">{title}</h3>
        <span className="tabular-nums text-[15px] text-text-primary">{value}</span>
      </header>
      <svg
        viewBox="0 0 100 100"
        preserveAspectRatio="none"
        // An inline chart cannot be an <img>; the role is what gives it an
        // accessible name instead of being skipped as decoration.
        // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role
        role="img"
        aria-label={`${title}: ${value}`}
        className="h-16 w-full"
      >
        {points === "" ? null : (
          <>
            <polyline
              points={`0,100 ${points} 100,100`}
              fill={stroke}
              fillOpacity={0.12}
              stroke="none"
            />
            <polyline
              points={points}
              fill="none"
              stroke={stroke}
              strokeWidth={1.5}
              // The viewBox is stretched to the element's width, so an
              // unscaled stroke would be drawn as a wildly fat horizontal
              // line and a hairline vertical one.
              vectorEffect="non-scaling-stroke"
              strokeLinejoin="round"
            />
          </>
        )}
      </svg>
      {/* The Mac's charts carry a seconds axis; this is the same statement in
          the space a sparkline has. */}
      <footer className="flex justify-between text-[10px] tabular-nums text-text-tertiary">
        <span>0s</span>
        <span>{span}s</span>
      </footer>
    </section>
  )
}
