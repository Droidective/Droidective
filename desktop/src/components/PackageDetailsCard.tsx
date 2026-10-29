import { useState, type ReactNode } from "react"
import { CheckCircle2, ChevronDown, ChevronRight, Download, XCircle } from "lucide-react"

import { formatBytes } from "@/lib/files"
import type { InstallOutcome, PackageDetails } from "@/lib/wire"

/**
 * What an app package is — the Mac's `PackageDetailsCard`.
 *
 * Name and package, version, the Android versions it needs and targets, what
 * the file holds, native code, launcher, signer and permissions, then each
 * device's outcome, then whatever the screen adds below. The lines arrive
 * worded by the daemon from the same ADBKit text the Mac reads, so this lays
 * them out and says nothing of its own.
 */
export function PackageDetailsCard({
  path,
  details,
  failed,
  outcomes,
  children,
}: {
  path: string
  /** Null while the daemon reads it. */
  details: PackageDetails | null
  /** Why the read itself failed, when it did. */
  failed: string | null
  outcomes: readonly InstallOutcome[]
  children?: ReactNode
}) {
  const fileName = path.split(/[\\/]/u).pop() ?? path
  return (
    <div className="flex w-full max-w-[560px] flex-col gap-3 rounded-[14px] border border-border-subtle bg-bg-surface p-4">
      <header className="flex items-start gap-3">
        <span className="flex size-[30px] shrink-0 items-center justify-center rounded-md bg-accent text-accent-fg">
          <Download size={18} />
        </span>
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <p className="truncate text-[15px] font-medium text-text-primary">
              {details?.label ?? fileName}
            </p>
            {details?.isDebuggable === true ? (
              <span
                className="shrink-0 rounded-full bg-warn/15 px-1.5 py-0.5 text-[10px] font-medium text-warn"
                title="Built debuggable — a debug build, or a release build with debugging left on"
              >
                Debuggable
              </span>
            ) : null}
          </div>
          {details === null || details.packageName === null ? null : (
            <p className="truncate text-[11.5px] text-text-tertiary" data-selectable>
              {details.packageName}
            </p>
          )}
        </div>
      </header>

      {details === null ? (
        <p className="text-[11.5px] text-text-tertiary">
          {failed ?? "Reading the package…"}
        </p>
      ) : (
        <Facts details={details} />
      )}

      {outcomes.map((outcome) => (
        <div key={outcome.serial} className="flex items-start gap-2">
          {outcome.ok ? (
            <CheckCircle2 size={14} className="mt-0.5 shrink-0 text-accent" />
          ) : (
            <XCircle size={14} className="mt-0.5 shrink-0 text-danger" />
          )}
          <div className="min-w-0">
            <p className="text-text-primary">{outcome.serial}</p>
            {outcome.ok ? null : (
              <p className="break-words text-[11.5px] text-warn" data-selectable>
                {outcome.message}
              </p>
            )}
          </div>
        </div>
      ))}

      {children}
    </div>
  )
}

function Facts({ details }: { details: PackageDetails }) {
  const [showsPermissions, setShowsPermissions] = useState(false)
  const rows: [string, string | null, boolean?][] = [
    ["Version", details.version],
    ["Requires", details.requires],
    ["Targets", details.targets],
    ["File", `${details.fileName} · ${formatBytes(details.fileSizeBytes)}`],
    ["Contains", details.contents],
    ["Native code", details.nativeCode],
    ["Opens", details.launcher, details.hasNoLauncher],
    ["Signed by", details.signer],
  ]
  const count = details.permissions.length
  return (
    <div className="flex flex-col gap-2">
      <dl className="grid grid-cols-[auto_1fr] gap-x-3.5 gap-y-1.5">
        {rows.map(([label, value, warns]) =>
          value === null ? null : (
            <div key={label} className="contents">
              <dt className="text-[11.5px] text-text-tertiary">{label}</dt>
              <dd
                className={`min-w-0 break-words ${warns === true ? "text-warn" : "text-text-primary"}`}
                data-selectable
              >
                {value}
              </dd>
            </div>
          ),
        )}
      </dl>
      {count === 0 ? null : (
        <div className="flex flex-col gap-1">
          <button
            type="button"
            onClick={() => setShowsPermissions((shown) => !shown)}
            className="flex items-center gap-1 self-start text-[11.5px] text-text-tertiary"
          >
            {showsPermissions ? <ChevronDown size={11} /> : <ChevronRight size={11} />}
            {count} permission{count === 1 ? "" : "s"}
          </button>
          {showsPermissions ? (
            <pre className="pl-3.5 font-mono text-[11px] text-text-secondary" data-selectable>
              {details.permissions.join("\n")}
            </pre>
          ) : null}
        </div>
      )}
      {details.note === null ? null : (
        <p className="text-[11.5px] text-text-tertiary">{details.note}</p>
      )}
    </div>
  )
}
