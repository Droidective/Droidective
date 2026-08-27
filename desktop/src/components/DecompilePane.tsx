import { ApkToolNotice } from "@/components/ApkToolNotice"
import { DecompileBrowser, MODES } from "@/components/DecompileBrowser"
import { HubSection } from "@/components/Hub"
import { missingTools, useApkToolchain } from "@/hooks/useApkToolchain"
import { useDecompile, type Decompile } from "@/hooks/useDecompile"

/**
 * APK Decompile — the Mac's `DecompileView`.
 *
 * jadx or apktool over one APK, then its output as a tree with a source
 * viewer, a content search, and (for apktool) a rebuild. Device-free: an APK
 * is a file on this machine, so the screen works with nothing connected.
 *
 * `apkPath` is for APK Studio, which has already loaded one — the standalone
 * feature passes nothing and asks.
 *
 * The output root travels back to the daemon on every read and search, which
 * is what confines them to it (`DecompileProtocol.confined`). Nothing here
 * decides what may be read; it only carries the root the daemon handed out.
 */
export function DecompilePane({ apkPath = null }: { apkPath?: string | null }) {
  const tools = useApkToolchain()
  const state = useDecompile(apkPath)
  const tree = state.tree

  if (tree === null) {
    return (
      <div className="flex h-full flex-col gap-3 overflow-auto p-4">
        {/* Only Java: jadx and apktool are downloaded on first use, and the
            build-tools this screen does not touch. */}
        <ApkToolNotice missing={missingTools(tools, ["java"])} />
        <Chooser state={state} />
      </div>
    )
  }
  return <DecompileBrowser state={state} tree={tree} />
}

function Chooser({ state }: { state: Decompile }) {
  const path = state.path
  return (
    <HubSection
      title="APK Decompile"
      subtitle="Decompile an APK to readable sources, then browse and search them."
    >
      <div className="flex flex-col gap-2">
        {MODES.map((one) => (
          <label
            key={one.id}
            aria-label={one.title}
            className="flex cursor-pointer items-start gap-2 rounded border border-border-subtle p-2"
          >
            <input
              type="radio"
              name="decompile-mode"
              checked={state.mode === one.id}
              onChange={() => state.setMode(one.id)}
              className="mt-1 accent-accent"
            />
            <span className="min-w-0">
              <span className="text-text-primary">{one.title}</span>
              <span className="block text-[11.5px] text-text-tertiary">{one.blurb}</span>
            </span>
          </label>
        ))}
        {state.toolReady === false ? (
          <ToolGate mode={state.mode} installing={state.installing} onInstall={state.install} />
        ) : (
          <button
            type="button"
            disabled={state.busy}
            onClick={path === null ? state.choose : () => state.run(false)}
            className="mt-1 self-start rounded bg-accent px-3 py-1 text-white disabled:opacity-40"
          >
            {buttonLabel(state.busy, path)}
          </button>
        )}
        {path === null ? null : (
          <p className="truncate text-[11.5px] text-text-tertiary" title={path}>
            {path}
          </p>
        )}
      </div>
    </HubSection>
  )
}

/**
 * The decompiler is a download, and this is where that is said.
 *
 * Before this the run simply failed with "a tool this needs is not installed"
 * and nothing to click — a dead end on any machine that had not already fetched
 * it, which is every fresh one. The size is named because it is tens of
 * megabytes and the wait is otherwise unexplained.
 */
function ToolGate({
  mode,
  installing,
  onInstall,
}: {
  mode: string
  installing: boolean
  onInstall: () => void
}) {
  return (
    <div className="mt-1 flex flex-col items-start gap-1.5 rounded border border-border-subtle p-2.5">
      <p className="text-text-primary">{mode} is not downloaded yet.</p>
      <p className="text-[11.5px] text-text-tertiary">
        It is fetched once from its GitHub release — tens of megabytes — and kept for next time.
      </p>
      <button
        type="button"
        disabled={installing}
        onClick={onInstall}
        className="mt-0.5 rounded bg-accent px-3 py-1 text-white disabled:opacity-40"
      >
        {installing ? `Downloading ${mode}…` : `Download ${mode}`}
      </button>
    </div>
  )
}

function buttonLabel(busy: boolean, path: string | null): string {
  if (busy) return "Decompiling…"
  return path === null ? "Choose APK…" : "Decompile"
}
