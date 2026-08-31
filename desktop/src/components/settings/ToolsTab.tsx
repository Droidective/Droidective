import { useCallback, useEffect, useState } from "react"
import { Download, RefreshCw, Trash2 } from "lucide-react"

import { Banner, Button } from "@/components/Controls"
import { Section } from "@/components/settings/SettingsKit"
import { ConfirmDialog } from "@/components/ConfirmDialog"
import {
  asDaemonError,
  managedToolInstall,
  managedToolList,
  managedToolRemove,
} from "@/lib/daemon"
import {
  toolAction,
  toolName,
  toolPurpose,
  toolSizeLabel,
  toolVersionLabel,
  type ManagedToolEntry,
} from "@/lib/managed-tools"

/**
 * Settings ▸ Tools — the Mac's `ManagedToolsSettingsView`.
 *
 * What this host can download, what is on disk, and how much room it takes.
 * The list is the *host's* catalogue, so ffmpeg appears here on Windows and
 * Linux and not on macOS, where the app bundles one — the app never installs
 * a *system* tool, and these are not system tools.
 */
export function ToolsTab() {
  const [tools, setTools] = useState<ManagedToolEntry[]>([])
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [pendingRemove, setPendingRemove] = useState<ManagedToolEntry | null>(null)

  const load = useCallback(() => {
    setLoading(true)
    managedToolList().then(
      (answer) => {
        setTools(answer.tools)
        setError(null)
        setLoading(false)
      },
      (thrown: unknown) => {
        setError(asDaemonError(thrown).message)
        setLoading(false)
      },
    )
  }, [])

  useEffect(load, [load])

  const act = useCallback(
    (id: string, action: (id: string) => Promise<{ tools: ManagedToolEntry[] }>) => {
      setBusy(id)
      setError(null)
      action(id).then(
        (answer) => {
          setTools(answer.tools)
          setBusy(null)
        },
        (thrown: unknown) => {
          setError(asDaemonError(thrown).message)
          setBusy(null)
        },
      )
    },
    [],
  )

  return (
    <div className="flex flex-col gap-5">
      {error === null ? null : <Banner tone="error">{error}</Banner>}

      <Section title="Downloadable tools">
        {loading ? (
          <p className="px-1 py-2 text-text-secondary">Reading what&apos;s installed…</p>
        ) : tools.length === 0 ? (
          <p className="px-1 py-2 text-text-secondary">
            Nothing to download on this platform.
          </p>
        ) : (
          tools.map((tool) => (
            <ToolRow
              key={tool.id}
              tool={tool}
              busy={busy === tool.id}
              disabled={busy !== null}
              onInstall={() => {
                act(tool.id, managedToolInstall)
              }}
              onRemove={() => {
                setPendingRemove(tool)
              }}
            />
          ))
        )}
      </Section>

      <div>
        <Button disabled={loading || busy !== null} onClick={load}>
          <span className="flex items-center gap-1.5">
            <RefreshCw size={12} />
            Refresh
          </span>
        </Button>
      </div>

      <Footnote />

      {pendingRemove === null ? null : (
        <ConfirmDialog
          title={`Remove ${toolName(pendingRemove.id)}?`}
          message={`${toolSizeLabel(pendingRemove.sizeBytes)} is freed. It can be downloaded again.`}
          confirmLabel="Remove"
          onConfirm={() => {
            act(pendingRemove.id, managedToolRemove)
            setPendingRemove(null)
          }}
          onCancel={() => {
            setPendingRemove(null)
          }}
        />
      )}
    </div>
  )
}

/** Where these come from, and which tools are deliberately not here. */
function Footnote() {
  return (
    <p className="text-text-tertiary">
      These are downloaded from their projects&apos; own releases, at a version this build pinned,
      and verified against the release&apos;s digest. adb and the emulator are not here: the app
      never installs those — Settings ▸ Doctor says where to get them.
    </p>
  )
}

function ToolRow({
  tool,
  busy,
  disabled,
  onInstall,
  onRemove,
}: {
  tool: ManagedToolEntry
  busy: boolean
  disabled: boolean
  onInstall: () => void
  onRemove: () => void
}) {
  const action = toolAction(tool)

  return (
    <div className="flex items-center gap-3 py-2">
      <div className="min-w-0 flex-1">
        <p className="text-[13px] text-text-primary">{toolName(tool.id)}</p>
        <p className="text-text-tertiary">{toolPurpose(tool.id)}</p>
        <p className="text-text-secondary">
          {toolVersionLabel(tool)}
          {tool.installed ? ` · ${toolSizeLabel(tool.sizeBytes)}` : ""}
        </p>
      </div>
      {action === "installed" ? null : (
        <Button tone="primary" disabled={disabled} onClick={onInstall}>
          <span className="flex items-center gap-1.5">
            <Download size={12} />
            {busy ? "Downloading…" : action === "upgrade" ? "Upgrade" : "Download"}
          </span>
        </Button>
      )}
      {tool.installed ? (
        <Button disabled={disabled} onClick={onRemove} title={`Remove ${toolName(tool.id)}`}>
          <Trash2 size={12} />
        </Button>
      ) : null}
    </div>
  )
}
