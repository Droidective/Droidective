import { AlertTriangle, CheckCircle2, RefreshCw, Stethoscope, XCircle } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { Section } from "@/components/settings/SettingsKit"
import { useToolchain } from "@/hooks/useToolchain"
import { cn } from "@/lib/cn"
import { checkedTools, verdict, type Check } from "@/lib/doctor"
import type { ToolReport } from "@/lib/wire"

/**
 * Settings ▸ Doctor — the Mac's `DoctorSettingsView`.
 *
 * A verdict, a row per checked tool with its version and path, and Re-check.
 * A missing tool shows its **install hint** and nothing more: neither app ever
 * installs a tool itself, so pointing at where to get it is the whole answer.
 */
export function DoctorTab() {
  const { tools, error, detecting, redetect } = useToolchain()
  const summary = verdict(tools)

  return (
    <div className="flex flex-col gap-5">
      {error === null ? null : <Banner tone="error">{error.message}</Banner>}

      <Verdict tone={summary.tone} message={summary.message} />

      <Section title="Toolchain">
        {checkedTools(tools).map((row) => (
          <ToolRow key={row.check.id} check={row.check} report={row.report} />
        ))}
      </Section>

      <div>
        <Button
          disabled={detecting}
          onClick={() => {
            void redetect()
          }}
        >
          <span className="flex items-center gap-1.5">
            <RefreshCw size={12} />
            {detecting ? "Checking…" : "Re-check setup"}
          </span>
        </Button>
      </div>
    </div>
  )
}

function Verdict({ tone, message }: { tone: "pending" | "ok" | "warn"; message: string }) {
  const Icon = tone === "ok" ? CheckCircle2 : tone === "warn" ? AlertTriangle : Stethoscope
  const tint = tone === "ok" ? "text-accent" : tone === "warn" ? "text-warn" : "text-text-tertiary"
  return (
    <p className="flex items-center gap-2 text-text-primary">
      <Icon size={15} className={cn("shrink-0", tint)} />
      {message}
    </p>
  )
}

function ToolRow({ check, report }: { check: Check; report: ToolReport | null }) {
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        <Status report={report} />
        <span className="text-text-primary">{check.name}</span>
        <span className="flex-1" />
        {report?.installed === false ? (
          <span className="text-[11.5px] text-warn">not installed</span>
        ) : null}
        {report?.version === null || report?.version === undefined ? null : (
          <span className="max-w-[220px] truncate text-[11.5px] text-text-tertiary" data-selectable>
            {report.version}
          </span>
        )}
      </div>
      <p className="pl-[22px] text-[11.5px] text-text-tertiary">{check.purpose}</p>
      {report?.path === null || report?.path === undefined ? null : (
        <p className="pl-[22px] text-[11.5px] text-text-tertiary" data-selectable>
          {report.path}
        </p>
      )}
      {report?.installed === false ? (
        <p className="pl-[22px] text-[11.5px] text-text-secondary">{report.installHint}</p>
      ) : null}
    </div>
  )
}

function Status({ report }: { report: ToolReport | null }) {
  // Nothing known yet reads as neither installed nor missing, because it is.
  if (report === null) {
    return <Stethoscope size={14} className="shrink-0 text-text-tertiary" />
  }
  return report.installed ? (
    <CheckCircle2 size={14} className="shrink-0 text-accent" />
  ) : (
    <XCircle size={14} className="shrink-0 text-warn" />
  )
}
