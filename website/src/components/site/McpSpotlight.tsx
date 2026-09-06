import { McpFlow } from "@/components/site/ProductMocks"
import { Reveal } from "@/components/site/Reveal"

const points = [
  {
    lead: "10 tools, 8 resources",
    rest: ", the same contract as Reactotron's own MCP server, so any client that speaks it already works.",
  },
  {
    lead: "Redacted by default",
    rest: ". The MCP boundary strips sensitive values before your agent ever sees them. The in-app timeline is never touched.",
  },
  {
    lead: "Loopback only",
    rest: ", bound to 127.0.0.1 with Origin validation and an optional bearer token. Off until you turn it on.",
  },
]

/** MCP is the most differentiated thing Droidective does, so it gets its own
 *  spotlight rather than a cell in a feature grid. */
export function McpSpotlight() {
  return (
    <section id="mcp" className="relative overflow-hidden py-24 max-[620px]:py-14">
      {/* Ambient wash — marks this as a distinct moment in the page rhythm. */}
      <div
        aria-hidden
        className="pointer-events-none absolute top-0 left-1/2 h-[420px] w-[900px] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(105,161,6,0.07),transparent_70%)] blur-2xl"
      />
      <div aria-hidden className="glow-line mx-auto mb-24 max-w-[600px] max-[620px]:mb-16" />

      <div className="relative mx-auto grid max-w-[1120px] grid-cols-2 items-center gap-14 px-6 max-[940px]:grid-cols-1 max-[940px]:gap-10">
        <div className="min-w-0">
          <h2 className="display mb-5 text-[clamp(28px,4vw,42px)] leading-[1.06]">
            Your AI can finally{" "}
            <span className="text-green">see your app.</span>
          </h2>
          <p className="mb-7 text-[16.5px] leading-relaxed text-muted">
            Stop pasting logs into a chat window. Droidective runs an opt-in MCP server that hands your
            agent the live runtime: the Reactotron timeline, store state, and every network request from
            the app that's running right now.
          </p>

          <ul className="m-0 list-none p-0">
            {points.map((p) => (
              <li key={p.lead} className="relative border-t border-white/[0.05] py-3.5 pl-6 text-[14px] leading-relaxed text-muted/90 last:border-b">
                <span aria-hidden className="absolute top-3.5 left-0 font-mono font-bold text-green/70">
                  &gt;
                </span>
                <b className="font-semibold text-text">{p.lead}</b>
                {p.rest}
              </li>
            ))}
          </ul>
        </div>

        <Reveal className="min-w-0">
          <McpFlow />
        </Reveal>
      </div>
    </section>
  )
}
