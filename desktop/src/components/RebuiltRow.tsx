import { BadgeCheck } from "lucide-react"

import { revealPath } from "@/lib/daemon"

/**
 * What a rebuild wrote, and what to do with it — the Mac's `resultRow`.
 *
 * Two buttons rather than a toast, because the toast is gone by the time the
 * decision is made and the decision is the point: apktool's output will not
 * install until it is signed.
 *
 * `onSign` is APK Studio's, which has a Sign tab to hand it to. Standalone
 * there is nowhere to go, so the button is not offered — an unsigned APK on
 * disk with a reveal is what that screen can honestly do.
 */
export function RebuiltRow({
  path,
  onSign,
}: {
  path: string
  onSign?: ((path: string) => void) | undefined
}) {
  return (
    <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border-subtle bg-bg-surface px-3 py-2">
      <BadgeCheck size={13} className="shrink-0 text-ok" />
      <span className="min-w-0 flex-1 truncate text-[11.5px] text-text-secondary" title={path}>
        Rebuilt {path.split("/").pop()} — sign it before installing.
      </span>
      {onSign === undefined ? null : (
        <button
          type="button"
          onClick={() => onSign(path)}
          className="shrink-0 rounded bg-accent px-2 py-1 text-[11.5px] text-white"
        >
          Sign the rebuilt APK
        </button>
      )}
      <button
        type="button"
        // "Open in Finder" on the Mac; the documented platform-name exception,
        // and the wording the signer's own result row already uses here.
        onClick={() => void revealPath(path)}
        className="shrink-0 rounded border border-border-subtle px-2 py-1 text-[11.5px] text-text-secondary hover:bg-bg-hover"
      >
        Show in folder
      </button>
    </div>
  )
}
