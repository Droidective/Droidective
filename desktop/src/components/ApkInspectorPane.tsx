import { useCallback, useEffect, useState } from "react"

import { ApkToolNotice } from "@/components/ApkToolNotice"
import { HubColumn, HubRowList, HubSection } from "@/components/Hub"
import { missingTools, useApkToolchain } from "@/hooks/useApkToolchain"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, inspectApk, pickFile } from "@/lib/daemon"
import type { ApkReport } from "@/lib/wire"

/**
 * APK Inspector — the Mac's `ApkInspectorView`.
 *
 * Reads a package's manifest, permissions, SDK levels and signing certificates.
 * Device-free: it is a file on this machine, so the screen works with nothing
 * connected.
 *
 * `apkPath` is APK Studio handing over the APK it already has, which this then
 * inspects without asking again; the standalone feature passes nothing.
 */
export function ApkInspectorPane({ apkPath = null }: { apkPath?: string | null }) {
  const tools = useApkToolchain()
  const { show } = useNotifications()
  const [report, setReport] = useState<ApkReport | null>(null)
  const [busy, setBusy] = useState(false)

  const inspect = useCallback(
    (path: string) => {
      setBusy(true)
      void (async () => {
        try {
          setReport(await inspectApk(path))
        } catch (thrown) {
          show({ message: asDaemonError(thrown).message, ok: false })
        } finally {
          setBusy(false)
        }
      })()
    },
    [show],
  )

  useEffect(() => {
    if (apkPath !== null) inspect(apkPath)
  }, [apkPath, inspect])

  const choose = () => {
    void (async () => {
      try {
        const path = await pickFile("APK", ["apk"])
        // A dismissed dialog is a choice, not a failure.
        if (path !== null) inspect(path)
      } catch (thrown) {
        show({ message: asDaemonError(thrown).message, ok: false })
      }
    })()
  }

  return (
    <HubColumn>
      <ApkToolNotice missing={missingTools(tools, ["aapt2", "apksigner", "java"])} />

      {report === null ? (
        <HubSection title="APK Inspector" subtitle="Inspect an APK — manifest, permissions, SDK, signing.">
          <button
            type="button"
            disabled={busy}
            onClick={choose}
            className="self-start rounded bg-accent px-3 py-1 text-white disabled:opacity-40"
          >
            Choose APK…
          </button>
        </HubSection>
      ) : (
        <ApkDetail report={report} busy={busy} onChoose={apkPath === null ? choose : null} />
      )}
    </HubColumn>
  )
}

function ApkDetail({
  report,
  busy,
  onChoose,
}: {
  report: ApkReport
  busy: boolean
  /** Null inside APK Studio, which owns the choice itself. */
  onChoose: (() => void) | null
}) {
  return (
    <>
      <HubSection
        title={report.label ?? report.fileName}
        subtitle={report.packageName ?? report.fileName}
        accessory={
          // Null inside APK Studio: the studio owns which APK is loaded, and a
          // second chooser here would change this tab's APK while the others
          // kept the old one.
          onChoose === null ? null : (
            <button
              type="button"
              disabled={busy}
              onClick={onChoose}
              className="rounded border border-border-subtle px-2 py-1 text-[12px] text-text-primary hover:bg-bg-hover disabled:opacity-40"
            >
              Inspect another…
            </button>
          )
        }
      >
        <HubRowList
          rows={[
            { label: "File", value: report.fileName },
            { label: "Size", value: megabytes(report.fileSizeBytes) },
            { label: "Version", value: version(report) },
            { label: "Min SDK", value: report.minSdk ?? "—" },
            { label: "Target SDK", value: report.targetSdk ?? "—" },
            { label: "Debuggable", value: report.isDebuggable ? "Yes" : "No" },
          ]}
        />
        {!report.hasDetails && (
          // Says why this is all there is, rather than showing blanks that
          // read as an APK with no manifest.
          <p className="text-[11.5px] text-text-tertiary">
            Only the file itself could be read — aapt2 was not found, so the manifest was not
            parsed.
          </p>
        )}
      </HubSection>

      <ListSection title="Permissions" items={report.permissions} />
      <ListSection title="Features" items={report.features} />

      <HubSection title="Signing">
        {report.signers.length === 0 ? (
          <p className="text-text-tertiary">
            No signing certificate was read — the APK may be unsigned, or apksigner was not found.
          </p>
        ) : (
          <>
            <HubRowList
              rows={[{ label: "Schemes", value: report.signatureSchemes.join(", ") || "—" }]}
            />
            {report.signers.map((signer) => (
              <HubRowList
                key={signer.sha256 ?? signer.subjectDN ?? "signer"}
                rows={[
                  { label: "Subject", value: signer.subjectDN ?? "—" },
                  { label: "SHA-256", value: signer.sha256 ?? "—" },
                  { label: "SHA-1", value: signer.sha1 ?? "—" },
                ]}
              />
            ))}
          </>
        )}
      </HubSection>
    </>
  )
}

/** A titled list with its count, the way the Mac labels these. */
function ListSection({ title, items }: { title: string; items: string[] }) {
  return (
    <HubSection title={`${title} (${items.length})`}>
      {items.length === 0 ? (
        <p className="text-text-tertiary">None declared.</p>
      ) : (
        <div className="flex flex-col gap-0.5">
          {items.map((item) => (
            <span key={item} className="font-mono text-[11.5px] text-text-secondary">
              {item}
            </span>
          ))}
        </div>
      )}
    </HubSection>
  )
}

function version(report: ApkReport): string {
  if (report.versionName === null && report.versionCode === null) return "—"
  const name = report.versionName ?? "?"
  return report.versionCode === null ? name : `${name} (${report.versionCode})`
}

function megabytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} bytes`
  const mb = bytes / (1024 * 1024)
  return mb < 1 ? `${Math.round(bytes / 1024)} KB` : `${mb.toFixed(1)} MB`
}
