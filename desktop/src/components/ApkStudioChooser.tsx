import { ApkToolNotice } from "@/components/ApkToolNotice"
import { HubSection } from "@/components/Hub"
import { missingTools, useApkToolchain } from "@/hooks/useApkToolchain"

/**
 * APK Studio before an APK is loaded.
 *
 * Its own file so the studio itself stays about the tabs. The tool notice names
 * all three tools up front rather than per tab: someone without aapt2 finds out
 * when they pick a file, not three tabs later.
 */
export function ApkStudioChooser({ onChoose }: { onChoose: () => void }) {
  const tools = useApkToolchain()
  return (
    <div className="flex h-full flex-col gap-3 overflow-auto p-4">
      <ApkToolNotice missing={missingTools(tools, ["aapt2", "apksigner", "java"])} />
      <HubSection title="APK Studio" subtitle="Inspect, decompile, and sign one APK in one place.">
        <button
          type="button"
          onClick={onChoose}
          className="self-start rounded bg-accent px-3 py-1 text-white"
        >
          Choose APK…
        </button>
      </HubSection>
    </div>
  )
}
