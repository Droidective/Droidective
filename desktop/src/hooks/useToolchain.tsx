import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react"
import { asDaemonError, detectTools } from "@/lib/daemon"
import { adbMissing } from "@/lib/doctor"
import type { DaemonError, ToolReport } from "@/lib/wire"

export interface Toolchain {
  tools: ToolReport[]
  error: DaemonError | null
  detecting: boolean
  /** Null until adb has actually been looked for. */
  adbMissing: boolean | null
  /** How to get adb *on this machine* — the daemon words it per platform. */
  adbHint: string
  redetect: () => Promise<void>
}

const ToolchainContext = createContext<Toolchain | null>(null)

/**
 * What is installed on this machine, for the whole window.
 *
 * A context because two surfaces read the same answer — Settings ▸ Doctor and
 * the device bar's adb warning — and detecting twice would run four `--version`
 * subprocesses for one fact. Detected once on launch and on demand after that,
 * which is what the Mac's Doctor does with its Re-check button.
 */
export function ToolchainProvider({ children }: { children: React.ReactNode }) {
  const [tools, setTools] = useState<ToolReport[]>([])
  const [error, setError] = useState<DaemonError | null>(null)
  const [detecting, setDetecting] = useState(false)

  const redetect = useCallback(async () => {
    setDetecting(true)
    setError(null)
    try {
      const response = await detectTools()
      setTools(response.tools)
    } catch (thrown) {
      setError(asDaemonError(thrown))
    } finally {
      setDetecting(false)
    }
  }, [])

  useEffect(() => {
    void redetect()
  }, [redetect])

  const value = useMemo<Toolchain>(
    () => ({
      tools,
      error,
      detecting,
      adbMissing: adbMissing(tools),
      adbHint: tools.find((tool) => tool.id === "adb")?.installHint ?? "",
      redetect,
    }),
    [tools, error, detecting, redetect],
  )
  return <ToolchainContext value={value}>{children}</ToolchainContext>
}

export function useToolchain(): Toolchain {
  const value = useContext(ToolchainContext)
  if (value === null) throw new Error("useToolchain used outside ToolchainProvider")
  return value
}
