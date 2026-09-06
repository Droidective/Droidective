import { Boxes, FileCode2, KeyRound, ShieldCheck } from "lucide-react"

/** Window chrome shared by both mocks so they read as the same native app. */
function Chrome({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="overflow-hidden rounded-[14px] border border-white/[0.08] bg-gradient-to-b from-ink-700 to-ink-800">
      <div className="flex items-center gap-2.5 border-b border-white/[0.06] bg-ink-900/40 px-3.5 py-2.5">
        <span className="flex gap-1.5">
          <i className="size-2.5 rounded-full bg-[#ff5f57]" />
          <i className="size-2.5 rounded-full bg-[#febc2e]" />
          <i className="size-2.5 rounded-full bg-[#28c840]" />
        </span>
        <span className="ml-2 font-mono text-[11.5px] text-muted/70">{title}</span>
      </div>
      {children}
    </div>
  )
}

/** APK Studio — no screenshot of this screen exists in the repo, so the mock
 *  shows the real tab names and the actual toolchain output shape. */
export function ApkMock() {
  const tabs = [
    { label: "Inspect", icon: Boxes, on: true },
    { label: "Decompile", icon: FileCode2, on: false },
    { label: "Recompile", icon: Boxes, on: false },
    { label: "Sign", icon: KeyRound, on: false },
  ]
  const rows = [
    ["package", "com.example.app"],
    ["versionName", "4.2.0 (4200)"],
    ["minSdkVersion", "24"],
    ["targetSdkVersion", "35"],
    ["signature", "RSA 2048 · SHA-256"],
  ]

  return (
    <Chrome title="APK Studio · app-release.apk">
      <div className="flex gap-1 border-b border-white/[0.06] px-3 py-2">
        {tabs.map((t) => (
          <span
            key={t.label}
            className={
              t.on
                ? "flex items-center gap-1.5 rounded-lg bg-green/12 px-2.5 py-1.5 font-mono text-[11px] font-medium text-green shadow-[inset_0_0_0_1px_rgba(105,161,6,0.2)]"
                : "flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 font-mono text-[11px] text-muted/50"
            }
          >
            <t.icon className="size-3.5" aria-hidden />
            {t.label}
          </span>
        ))}
      </div>
      <div className="p-4">
        <div className="mb-3 flex items-center gap-2 rounded-lg border border-green/12 bg-green/[0.05] px-3 py-2">
          <ShieldCheck className="size-4 shrink-0 text-green" aria-hidden />
          <span className="font-mono text-[11.5px] text-green/90">Signature verified · v2 scheme</span>
        </div>
        <dl className="m-0 grid grid-cols-[auto_1fr] gap-x-5 gap-y-2">
          {rows.map(([k, v]) => (
            <div key={k} className="col-span-2 grid grid-cols-subgrid border-b border-white/[0.04] pb-2 last:border-0">
              <dt className="font-mono text-[11.5px] text-faint/70">{k}</dt>
              <dd className="m-0 font-mono text-[11.5px] text-text/90">{v}</dd>
            </div>
          ))}
        </dl>
      </div>
    </Chrome>
  )
}

/** The MCP data path. Animated with CSS only (a pulsing dot per hop) so it
 *  costs nothing and honours prefers-reduced-motion via .cta-breathe. */
export function McpFlow() {
  const hops = [
    { label: "Claude Code · Cursor", sub: "MCP client" },
    { label: "Droidective", sub: "localhost:4567/mcp" },
    { label: "Your running app", sub: "Reactotron client" },
  ]

  return (
    <Chrome title="Settings ▸ MCP · server running">
      <div className="p-5">
        <ul className="m-0 list-none p-0">
          {hops.map((hop, i) => (
            <li key={hop.label}>
              <div className="flex items-center gap-3 rounded-xl border border-white/[0.06] bg-white/[0.02] px-3.5 py-3">
                <span className="relative flex size-2 shrink-0">
                  <span
                    className="cta-breathe absolute inline-flex size-full rounded-full bg-green"
                    style={{ animationDelay: `${i * 0.6}s` }}
                  />
                  <span className="relative inline-flex size-2 rounded-full bg-green" />
                </span>
                <span className="min-w-0">
                  <span className="block text-[13.5px] font-semibold">{hop.label}</span>
                  <span className="font-mono text-[10.5px] text-faint/70">{hop.sub}</span>
                </span>
              </div>
              {i < hops.length - 1 && (
                <div aria-hidden className="ml-[19px] h-4 w-px bg-gradient-to-b from-green/40 to-green/10" />
              )}
            </li>
          ))}
        </ul>
        <div className="mt-4 rounded-xl border border-white/[0.06] bg-ink-900/50 p-3.5">
          <p className="mb-2 font-mono text-[10.5px] tracking-[0.06em] text-faint/60 uppercase">ask your agent</p>
          <p className="font-mono text-[12px] leading-relaxed text-muted/90">
            <span className="text-green">&gt;</span> why is the cart state empty?
          </p>
          <p className="mt-1.5 font-mono text-[12px] leading-relaxed text-muted/90">
            <span className="text-green">&gt;</span> which network request failed?
          </p>
        </div>
      </div>
    </Chrome>
  )
}
