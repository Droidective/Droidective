import { TriangleAlert } from "lucide-react"

/**
 * What is missing, and where it comes from.
 *
 * Named per tool rather than "a tool is missing", because the two sources want
 * different things done: aapt2, apksigner and zipalign ship with the Android
 * SDK's build-tools and are *detected*, while bundletool is downloaded and Java
 * is the system's. Telling someone to install the wrong one wastes the trip.
 */
export function ApkToolNotice({ missing }: { missing: string[] }) {
  if (missing.length === 0) return null
  return (
    <div className="flex items-start gap-2 rounded-lg border border-border-subtle bg-bg-surface p-3">
      <TriangleAlert size={14} className="mt-0.5 shrink-0 text-text-tertiary" />
      <div className="min-w-0">
        <p className="text-text-primary">
          {missing.length === 1 ? "A tool this needs" : "Some tools this needs"} could not be found:{" "}
          {missing.join(", ")}.
        </p>
        <p className="mt-0.5 text-[11.5px] text-text-tertiary">{advice(missing)}</p>
      </div>
    </div>
  )
}

function advice(missing: string[]): string {
  const sdk = missing.filter((tool) => SDK_TOOLS.has(tool))
  const lines: string[] = []
  if (sdk.length > 0) {
    lines.push(
      `${sdk.join(" and ")} ship with the Android SDK's build-tools — install them through Android Studio's SDK Manager.`,
    )
  }
  if (missing.includes("java")) {
    lines.push("Java is needed to run the signing and bundle tools; install a JDK.")
  }
  if (missing.includes("bundletool")) {
    lines.push("bundletool is downloaded on first use; check the network and try again.")
  }
  return lines.join(" ")
}

const SDK_TOOLS = new Set(["aapt2", "apksigner", "zipalign"])
