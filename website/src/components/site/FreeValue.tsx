import { Reveal } from "@/components/site/Reveal"
import { GITHUB_URL } from "@/lib/content"

/** Every figure here is checked against the repo: MIT LICENSE, 59 FeatureDefs
 *  in FeatureRegistry, and no paid tier or paywalled path anywhere in the app.
 *  No download CTA on purpose — the nav, hero, and closing CTA already carry it. */
const lineItems = [
  ["59 developer tools", "0.00"],
  ["Screen mirroring & recording", "0.00"],
  ["Reactotron + MCP server", "0.00"],
  ["APK Studio & Frida setup", "0.00"],
  ["Every future update", "0.00"],
]

export function FreeValue() {
  return (
    <section className="mx-auto max-w-[1120px] px-6 py-24 max-[620px]:py-16">
      <Reveal>
        <div className="relative overflow-hidden rounded-3xl border border-white/[0.06] bg-gradient-to-b from-white/[0.03] to-white/[0.01] px-10 py-14 max-[620px]:px-6 max-[620px]:py-11">
          <div
            aria-hidden
            className="pointer-events-none absolute -top-24 -right-16 h-[320px] w-[420px] rounded-full bg-[radial-gradient(closest-side,rgba(105,161,6,0.08),transparent_70%)] blur-2xl"
          />

          <div className="relative grid grid-cols-[1fr_auto] items-center gap-14 max-[940px]:grid-cols-1 max-[940px]:gap-10">
            <div className="min-w-0">
              <p className="mb-5 font-mono text-[12px] font-medium tracking-[0.06em] text-green/80 uppercase">
                <span className="mr-2 text-green-dim/60">&gt;_</span>
                the pricing page
              </p>
              <h2 className="mb-6 text-[clamp(34px,5vw,56px)] leading-[0.98] font-extrabold tracking-[-0.04em]">
                59 tools.
                <br />
                <span className="text-green">$0.</span>
              </h2>
              <p className="mb-4 max-w-[42ch] text-[16.5px] leading-relaxed text-muted">
                No pro tier. No trial countdown. No “contact sales.” Your wallet can sit this debugging
                session out.
              </p>
              <p className="max-w-[42ch] text-[14.5px] leading-relaxed text-muted/70">
                If it saves you an afternoon,{" "}
                <a
                  href={GITHUB_URL}
                  className="font-semibold text-green/90 underline decoration-green/30 underline-offset-4 transition-colors duration-200 hover:text-green hover:decoration-green/60"
                >
                  ⭐ star the repo
                </a>
                . That's the entire business model.
              </p>
            </div>

            {/* Receipt */}
            <div className="w-[320px] shrink-0 rounded-xl border border-white/[0.07] bg-ink-900/50 p-5 font-mono max-[940px]:w-full">
              <p className="mb-1 text-[11px] tracking-[0.1em] text-faint/60 uppercase">Droidective</p>
              <p className="mb-4 text-[10.5px] text-faint/40">MIT · open source · macOS 14+</p>

              <ul className="m-0 list-none p-0">
                {lineItems.map(([label, price]) => (
                  <li key={label} className="flex items-baseline gap-2 py-1.5 text-[11.5px]">
                    <span className="text-muted/75">{label}</span>
                    <span aria-hidden className="min-w-4 flex-1 border-b border-dashed border-white/[0.09]" />
                    <span className="text-muted/50">${price}</span>
                  </li>
                ))}
              </ul>

              <div className="my-3 border-t border-dashed border-white/[0.12]" />
              <div className="flex items-baseline justify-between">
                <span className="text-[12px] font-bold tracking-[0.06em] text-text uppercase">Total</span>
                <span className="text-[19px] font-bold text-green">$0.00</span>
              </div>
              <p className="mt-4 border-t border-white/[0.05] pt-3 text-[10.5px] leading-relaxed text-faint/50">
                Paid with: 1 GitHub star
                <br />
                <span className="text-faint/35">(optional, non-refundable)</span>
              </p>
            </div>
          </div>
        </div>
      </Reveal>
    </section>
  )
}
