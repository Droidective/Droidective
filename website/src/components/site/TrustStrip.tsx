import CountUp from "@/components/CountUp"
import { Reveal } from "@/components/site/Reveal"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"
import { APP_VERSION, BETA_RELEASE_URL, GITHUB_URL } from "@/lib/content"

/** The confidence signal, directly under the hero rather than inside it: the
 *  hero carries the value proposition and the CTA, this carries the facts that
 *  make the CTA safe to press.
 *
 *  Four facts in a divided row, not a run of middle-dots. Dot-separated lists
 *  read as one long string; a rule between cells reads as four separate claims,
 *  which is what these are. */
const facts: { value: string; label: string; href?: string }[] = [
  { value: APP_VERSION, label: "Latest release", href: `${GITHUB_URL}/releases/tag/${APP_VERSION}` },
  { value: "MIT", label: "Free and open source", href: `${GITHUB_URL}/blob/main/LICENSE` },
  { value: "macOS 14+", label: "Signed and notarized" },
  { value: "Windows · Linux", label: "On the beta channel", href: BETA_RELEASE_URL },
]

export function TrustStrip() {
  const reducedMotion = usePrefersReducedMotion()

  return (
    <section className="px-6 pb-10">
      <Reveal className="mx-auto max-w-[1020px]">
        <div className="shell">
          <div className="core grid grid-cols-[auto_1fr] items-stretch gap-px overflow-hidden max-[860px]:grid-cols-1">
            {/* The headline number carries its own weight, so it sits outside
                the divided cells rather than becoming a fifth one. */}
            <div className="flex items-center gap-3 px-7 py-5 max-[860px]:justify-center">
              <span className="tnum text-[34px] leading-none font-semibold text-green">
                {reducedMotion ? 61 : <CountUp to={61} duration={1.4} />}
              </span>
              <span className="max-w-[10ch] text-[13px] leading-[1.3] text-muted">
                tools in one workspace
              </span>
            </div>

            <dl className="grid grid-cols-4 max-[860px]:grid-cols-2">
              {facts.map((fact) => {
                const body = (
                  <>
                    <dt className="tnum text-[13px] font-medium text-text">{fact.value}</dt>
                    <dd className="mt-0.5 text-[11.5px] leading-snug text-faint">{fact.label}</dd>
                  </>
                )
                return (
                  <div
                    key={fact.label}
                    className="border-l border-white/[0.05] px-5 py-5 max-[860px]:border-t max-[860px]:first:border-t-0 max-[860px]:nth-2:border-t-0"
                  >
                    {fact.href ? (
                      <a
                        href={fact.href}
                        className="block transition-colors duration-700 ease-[cubic-bezier(0.32,0.72,0,1)] hover:[&>dt]:text-green"
                      >
                        {body}
                      </a>
                    ) : (
                      body
                    )}
                  </div>
                )
              })}
            </dl>
          </div>
        </div>
      </Reveal>
    </section>
  )
}
