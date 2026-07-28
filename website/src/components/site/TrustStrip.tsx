import CountUp from "@/components/CountUp"
import { Reveal } from "@/components/site/Reveal"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"

export function TrustStrip() {
  const reducedMotion = usePrefersReducedMotion()

  const items = [
    {
      value: reducedMotion ? <>59</> : <CountUp to={59} duration={1.4} />,
      label: "built-in tools",
      green: true,
    },
    { value: <>⌘T</>, label: "command palette", green: false },
    { value: <>MIT</>, label: "open source", green: false },
    { value: <>$0</>, label: "free, forever", green: false },
  ]

  return (
    <section className="relative px-6 py-4">
      {/* Glow line above */}
      <div aria-hidden className="glow-line mx-auto mb-4 max-w-[800px]" />
      <Reveal>
        <div className="mx-auto max-w-[820px] overflow-hidden rounded-2xl border border-white/[0.06] bg-gradient-to-b from-white/[0.03] to-white/[0.01] shadow-[0_20px_60px_-20px_rgba(0,0,0,0.5)]">
          <div className="grid grid-cols-4 max-[620px]:grid-cols-2">
            {items.map((item, i) => (
              <div
                key={item.label}
                className={[
                  "border-l border-white/[0.04] px-5 py-6 text-center first:border-l-0",
                  i === 1 ? "max-[620px]:border-l-0" : "",
                  i >= 2 ? "max-[620px]:border-t max-[620px]:border-t-white/[0.04]" : "",
                ].join(" ")}
              >
                <div
                  className={`font-mono text-[28px] font-bold tracking-[-0.02em] ${item.green ? "text-green" : "text-text"}`}
                >
                  {item.value}
                </div>
                <div className="mt-1.5 text-[12.5px] text-muted/80">{item.label}</div>
              </div>
            ))}
          </div>
        </div>
      </Reveal>
      {/* Glow line below */}
      <div aria-hidden className="glow-line mx-auto mt-4 max-w-[800px]" />
    </section>
  )
}
