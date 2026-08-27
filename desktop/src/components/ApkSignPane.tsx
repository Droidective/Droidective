import { useEffect, useState } from "react"

import { ApkAction, ApkFileRow, ApkPasswordField, ApkTextField } from "@/components/ApkControls"
import { ApkToolNotice } from "@/components/ApkToolNotice"
import { HubColumn, HubSection } from "@/components/Hub"
import { missingTools, useApkToolchain } from "@/hooks/useApkToolchain"
import { useNotifications } from "@/hooks/useNotifications"
import { signedApkName } from "@/lib/apk-sign"
import { asDaemonError, pickFile, pickFolder, revealPath, signApk } from "@/lib/daemon"

interface Keystore {
  path: string | null
  storePassword: string
  keyAlias: string
  keyPassword: string
}

/**
 * Sign APK — the Mac's `ApkSignView`.
 *
 * Zipalign and sign with your own keystore. Device-free: everything here is a
 * file on this machine.
 *
 * `apkPath` is APK Studio handing over the APK it already has; the standalone
 * feature passes nothing and asks for one.
 */
export function ApkSignPane({ apkPath = null }: { apkPath?: string | null }) {
  const tools = useApkToolchain()
  const { show } = useNotifications()
  const [apk, setApk] = useState<string | null>(apkPath)

  // The studio can load a different APK while this tab is mounted.
  useEffect(() => {
    if (apkPath !== null) setApk(apkPath)
  }, [apkPath])
  const [keystore, setKeystore] = useState<Keystore>({
    path: null,
    storePassword: "",
    keyAlias: "",
    keyPassword: "",
  })
  const [signed, setSigned] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

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

  const sign = () =>
    void guard(async () => {
      if (apk === null || keystore.path === null) return
      const directory = await pickFolder()
      // A dismissed folder picker is a choice, not a failure.
      if (directory === null) return
      // Never the input's own name: an output landing on the APK being read
      // would destroy the unsigned original, and there is no undo.
      const result = await signApk(apk, `${directory}/${signedApkName(apk)}`, {
        path: keystore.path,
        storePassword: keystore.storePassword,
        keyAlias: blankToNull(keystore.keyAlias),
        keyPassword: blankToNull(keystore.keyPassword),
      })
      setSigned(result.output)
      show({ message: result.message, ok: result.ok })
    })

  return (
    <HubColumn>
      <ApkToolNotice missing={missingTools(tools, ["apksigner", "zipalign", "java"])} />
      <HubSection title="Sign APK" subtitle="Zipalign and sign an APK with your keystore.">
        <SignForm
          apk={apk}
          embedded={apkPath !== null}
          keystore={keystore}
          busy={busy}
          onPick={(set, label, extensions) =>
            void guard(async () => {
              const path = await pickFile(label, extensions)
              if (path !== null) set(path)
            })
          }
          setApk={setApk}
          setKeystore={setKeystore}
          onSign={sign}
        />
      </HubSection>

      {signed !== null && (
        <HubSection title="Signed" subtitle={signed}>
          <ApkAction label="Show in folder" onClick={() => void revealPath(signed)} />
        </HubSection>
      )}
    </HubColumn>
  )
}

function SignForm({
  apk,
  embedded,
  keystore,
  busy,
  onPick,
  setApk,
  setKeystore,
  onSign,
}: {
  apk: string | null
  /** True when APK Studio handed the APK over and owns the choice. */
  embedded: boolean
  keystore: Keystore
  busy: boolean
  onPick: (set: (path: string) => void, label: string, extensions: string[]) => void
  setApk: (path: string | null) => void
  setKeystore: (keystore: Keystore) => void
  onSign: () => void
}) {
  // A keystore with no password cannot be opened, so the button says so by
  // staying disabled rather than letting the run fail on it.
  const ready = apk !== null && keystore.path !== null && keystore.storePassword !== ""

  return (
    <>
      {/* Inside APK Studio the studio owns the APK, so this row would be a
          second way to change it and leave the other tabs behind. The file is
          still named — just in the studio's own header. */}
      {embedded ? null : (
        <ApkFileRow
          label="APK"
          path={apk}
          chooseLabel="Choose APK…"
          changeLabel="Choose a different APK…"
          onChoose={() => onPick(setApk, "APK", ["apk"])}
        />
      )}
      <ApkFileRow
        label="Keystore"
        path={keystore.path}
        chooseLabel="Choose keystore…"
        changeLabel="Choose a different keystore…"
        onChoose={() =>
          onPick((path) => setKeystore({ ...keystore, path }), "Keystore", [
            "jks",
            "keystore",
            "p12",
          ])
        }
      />
      <ApkPasswordField
        label="Store password"
        value={keystore.storePassword}
        onChange={(storePassword) => setKeystore({ ...keystore, storePassword })}
      />
      <ApkTextField
        label="Key alias"
        value={keystore.keyAlias}
        onChange={(keyAlias) => setKeystore({ ...keystore, keyAlias })}
        placeholder="optional"
      />
      <ApkPasswordField
        label="Key password"
        value={keystore.keyPassword}
        onChange={(keyPassword) => setKeystore({ ...keystore, keyPassword })}
        placeholder="same as store password"
      />
      <button
        type="button"
        disabled={busy || !ready}
        onClick={onSign}
        className="self-start rounded bg-accent px-3 py-1 text-white disabled:cursor-not-allowed disabled:opacity-40"
      >
        {busy ? "Signing…" : "Sign APK"}
      </button>
    </>
  )
}

/** An empty optional field means "unset", not an empty password. */
function blankToNull(value: string): string | null {
  return value.trim() === "" ? null : value.trim()
}
