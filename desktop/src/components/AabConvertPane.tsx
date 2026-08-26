import { useState } from "react"

import { ApkAction, ApkFileRow, ApkPasswordField } from "@/components/ApkControls"
import { ApkToolNotice } from "@/components/ApkToolNotice"
import { HubColumn, HubSection } from "@/components/Hub"
import { missingTools, useApkToolchain } from "@/hooks/useApkToolchain"
import { useNotifications } from "@/hooks/useNotifications"
import { useTargets } from "@/hooks/useTargets"
import { baseName } from "@/lib/apk-sign"
import {
  asDaemonError,
  convertAab,
  installPath,
  pickFile,
  pickFolder,
  revealPath,
} from "@/lib/daemon"
import type { Device } from "@/lib/wire"

interface Built {
  path: string
  sizeBytes: number
}

/**
 * AAB to APK — the Mac's `AabConvertView`.
 *
 * bundletool builds a universal APK from a bundle, which is the only way to
 * side-load one. A device is needed only for the install at the end, so the
 * conversion itself works with nothing connected.
 */
export function AabConvertPane({ device }: { device: Device | null }) {
  const tools = useApkToolchain()
  const { show } = useNotifications()
  const { serials } = useTargets()
  const [aab, setAab] = useState<string | null>(null)
  const [keystore, setKeystore] = useState<string | null>(null)
  const [storePassword, setStorePassword] = useState("")
  const [built, setBuilt] = useState<Built | null>(null)
  const [busy, setBusy] = useState(false)

  /** Run one step, reporting whatever went wrong in one place. */
  const guard = async (work: () => Promise<void>) => {
    setBusy(true)
    try {
      await work()
    } catch (thrown) {
      show({ message: asDaemonError(thrown).message, ok: false })
    } finally {
      setBusy(false)
    }
  }

  const install = () =>
    void guard(async () => {
      if (built === null) return
      const result = await installPath(serials, built.path)
      // Per device, not one collapsed verdict — the shape Install App reports.
      for (const outcome of result.outcomes) {
        show({ message: `${outcome.serial}: ${outcome.message}`, ok: outcome.ok })
      }
    })

  if (built !== null) {
    return (
      <ConvertedView
        built={built}
        device={device}
        busy={busy}
        onInstall={install}
        onAgain={() => {
          setBuilt(null)
          setAab(null)
        }}
      />
    )
  }

  return (
    <HubColumn>
      <ApkToolNotice missing={missingTools(tools, ["bundletool", "java"])} />
      <HubSection
        title="AAB to APK"
        subtitle="Convert an Android App Bundle into an installable APK."
      >
        <ConvertForm
          aab={aab}
          keystore={keystore}
          storePassword={storePassword}
          busy={busy}
          onPick={(set, label, extensions) =>
            void guard(async () => {
              const path = await pickFile(label, extensions)
              // A dismissed dialog is a choice, not a failure.
              if (path !== null) set(path)
            })
          }
          setAab={setAab}
          setKeystore={setKeystore}
          setStorePassword={setStorePassword}
          onConvert={() =>
            void guard(async () => {
              if (aab === null) return
              const directory = await pickFolder()
              if (directory === null) return
              setBuilt(
                await convertAab(
                  aab,
                  directory,
                  keystore === null
                    ? null
                    : { path: keystore, storePassword, keyAlias: null, keyPassword: null },
                ),
              )
            })
          }
        />
      </HubSection>
    </HubColumn>
  )
}

function ConvertForm({
  aab,
  keystore,
  storePassword,
  busy,
  onPick,
  setAab,
  setKeystore,
  setStorePassword,
  onConvert,
}: {
  aab: string | null
  keystore: string | null
  storePassword: string
  busy: boolean
  onPick: (set: (path: string) => void, label: string, extensions: string[]) => void
  setAab: (path: string | null) => void
  setKeystore: (path: string | null) => void
  setStorePassword: (value: string) => void
  onConvert: () => void
}) {
  return (
    <>
      <ApkFileRow
        label="Bundle"
        path={aab}
        chooseLabel="Choose AAB…"
        changeLabel="Change…"
        onChoose={() => onPick(setAab, "Android App Bundle", ["aab"])}
        onClear={() => setAab(null)}
      />
      <ApkFileRow
        label="Keystore"
        path={keystore}
        // Not "nothing chosen": bundletool signs with its own debug key, which
        // is a real default rather than an absence.
        empty="bundletool's debug key"
        chooseLabel="Choose…"
        changeLabel="Change…"
        onChoose={() => onPick(setKeystore, "Keystore", ["jks", "keystore", "p12"])}
      />
      {keystore !== null && (
        <ApkPasswordField
          label="Store password"
          value={storePassword}
          onChange={setStorePassword}
        />
      )}
      <button
        type="button"
        disabled={busy || aab === null}
        onClick={onConvert}
        className="self-start rounded bg-accent px-3 py-1 text-white disabled:cursor-not-allowed disabled:opacity-40"
      >
        {busy ? "Converting…" : "Convert to APK"}
      </button>
    </>
  )
}

/** What the converter produced, and what can be done with it. */
function ConvertedView({
  built,
  device,
  busy,
  onInstall,
  onAgain,
}: {
  built: Built
  device: Device | null
  busy: boolean
  onInstall: () => void
  onAgain: () => void
}) {
  return (
    <HubColumn>
      <HubSection title={baseName(built.path)} subtitle={built.path}>
        <div className="flex flex-wrap items-center gap-2">
          <ApkAction
            label="Install on device"
            disabled={busy || device === null}
            title={device === null ? "Connect a device to install onto" : undefined}
            onClick={onInstall}
          />
          <ApkAction label="Reveal in folder" onClick={() => void revealPath(built.path)} />
          <ApkAction label="Convert another bundle" onClick={onAgain} />
        </div>
        {device === null && (
          <p className="text-[11.5px] text-text-tertiary">Connect a device to install onto.</p>
        )}
      </HubSection>
    </HubColumn>
  )
}
