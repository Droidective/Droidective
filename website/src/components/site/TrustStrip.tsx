import CountUp from "@/components/CountUp"
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
    <section className="border-y border-border bg-ink-800">
      <div className="mx-auto grid max-w-[1120px] grid-cols-4 px-6 max-[620px]:grid-cols-2">
        {items.map((item, i) => (
          <div
            key={item.label}
            className={[
              "border-l border-border px-4.5 py-7.5 text-center first:border-l-0",
              i === 1 ? "max-[620px]:border-l-0" : "",
              i >= 2 ? "max-[620px]:border-t max-[620px]:border-t-border" : "",
            ].join(" ")}
          >
            <div
              className={`font-mono text-3xl font-bold tracking-[-0.02em] ${item.green ? "text-green" : "text-text"}`}
            >
              {item.value}
            </div>
            <div className="mt-1.25 text-[13px] text-muted">{item.label}</div>
          </div>
        ))}
      </div>
    </section>
  )
}
