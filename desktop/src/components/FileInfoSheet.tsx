import { useEffect, useState } from "react"
import { Button } from "@/components/Controls"
import { asDaemonError, fileInfo } from "@/lib/daemon"
import { formatBytes, leafName } from "@/lib/files"
import type { DaemonError, FileDetails } from "@/lib/wire"

/**
 * Get Info for one path — the Mac's `stat` sheet.
 *
 * Android's filesystems record no creation time, so Modified is the closest
 * signal there is and the sheet says so rather than showing a blank row.
 */
export function FileInfoSheet({
  serial,
  path,
  asRoot,
  onDismiss,
}: {
  serial: string
  path: string
  asRoot: boolean
  onDismiss: () => void
}) {
  const [details, setDetails] = useState<FileDetails | null>(null)
  const [missing, setMissing] = useState(false)
  const [error, setError] = useState<DaemonError | null>(null)

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onDismiss()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onDismiss])

  useEffect(() => {
    let live = true
    setDetails(null)
    setMissing(false)
    setError(null)
    fileInfo({ serial, path, asRoot })
      .then((response) => {
        if (!live) return
        setDetails(response.info)
        setMissing(response.info === null)
      })
      .catch((thrown: unknown) => {
        if (live) setError(asDaemonError(thrown))
      })
    return () => {
      live = false
    }
  }, [serial, path, asRoot])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      {/* The backdrop dismisses; the sheet swallows the click so it does not. */}
      <button
        type="button"
        aria-label="Dismiss"
        onClick={onDismiss}
        className="absolute inset-0 cursor-default"
      />
      <div className="relative flex w-[440px] max-w-full flex-col rounded-xl border border-border-subtle bg-bg-raised shadow-2xl">
        <header className="flex items-center gap-3 border-b border-border-subtle px-4 py-3">
          <h2 className="min-w-0 flex-1 truncate text-[15px] text-text-primary" title={path}>
            {leafName(path)}
          </h2>
          <Button onClick={onDismiss}>Done</Button>
        </header>

        <div className="flex flex-col gap-1.5 p-4" data-selectable>
          <Body details={details} missing={missing} error={error} path={path} />
        </div>
      </div>
    </div>
  )
}

function Body({
  details,
  missing,
  error,
  path,
}: {
  details: FileDetails | null
  missing: boolean
  error: DaemonError | null
  path: string
}) {
  if (error !== null) return <p className="text-danger">{error.message}</p>
  if (missing) return <p className="text-text-tertiary">The device could not read that path.</p>
  if (details === null) return <p className="text-text-tertiary">Reading file info…</p>
  return (
    <>
      <InfoRow label="Type" value={details.type} />
      {details.sizeBytes === null ? null : (
        <InfoRow label="Size" value={formatBytes(details.sizeBytes)} />
      )}
      <InfoRow label="Owner" value={details.owner} />
      <InfoRow label="Permissions" value={details.permissions} mono />
      <InfoRow label="Modified" value={details.modified} />
      <InfoRow label="Metadata changed" value={details.changed} />
      <InfoRow label="Path" value={path} mono />
      <p className="mt-2 text-[11.5px] text-text-tertiary">
        Android doesn’t record file creation time — Modified is the closest signal.
      </p>
    </>
  )
}

function InfoRow({ label, value, mono = false }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex gap-4 text-[13px]">
      <span className="w-[140px] shrink-0 text-text-tertiary">{label}</span>
      <span
        className={mono ? "min-w-0 flex-1 break-all font-mono text-[12px] text-text-primary" : "min-w-0 flex-1 break-all text-text-primary"}
      >
        {value}
      </span>
    </div>
  )
}
