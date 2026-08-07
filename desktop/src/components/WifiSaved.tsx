import { useState } from "react"
import { Clipboard, Eye, EyeOff, Lock } from "lucide-react"
import { IconButton } from "@/components/Hub"
import { revealedPassword, savedEmptyText } from "@/lib/network"
import { cn } from "@/lib/cn"
import type { SavedNetwork } from "@/lib/wire"

/**
 * The saved-networks card — the Mac's `savedCard`.
 *
 * A password only exists here on a rooted device, because it comes out of
 * `WifiConfigStore.xml`. Saying "Passwords need root" in the header is what
 * stops the absence reading as "this device has none saved", which is a
 * different and wrong conclusion.
 */
export function WifiSaved({
  networks,
  hasRoot,
  loaded,
  onCopy,
}: {
  networks: SavedNetwork[]
  hasRoot: boolean
  loaded: boolean
  onCopy: (password: string) => void
}) {
  const [revealed, setRevealed] = useState<ReadonlySet<string>>(new Set())

  const toggle = (ssid: string) => {
    setRevealed((current) => {
      const next = new Set(current)
      if (next.has(ssid)) {
        next.delete(ssid)
      } else {
        next.add(ssid)
      }
      return next
    })
  }

  return (
    <section className="flex flex-col gap-2 rounded-[10px] bg-bg-surface p-3.5">
      <header className="flex items-center gap-3">
        <h2 className="min-w-0 flex-1 text-[13px] font-semibold text-text-primary">
          Saved networks
        </h2>
        {hasRoot ? null : (
          <span className="flex shrink-0 items-center gap-1 text-[11.5px] text-text-tertiary">
            <Lock size={11} />
            Passwords need root
          </span>
        )}
      </header>

      {networks.length === 0 ? (
        <p className="text-text-tertiary">{savedEmptyText(loaded)}</p>
      ) : (
        <div className="flex flex-col">
          {networks.map((network, index) => (
            <Row
              key={network.id}
              network={network}
              revealed={revealed.has(network.ssid)}
              divided={index > 0}
              onToggle={() => {
                toggle(network.ssid)
              }}
              onCopy={onCopy}
            />
          ))}
        </div>
      )}
    </section>
  )
}

function Row({
  network,
  revealed,
  divided,
  onToggle,
  onCopy,
}: {
  network: SavedNetwork
  revealed: boolean
  divided: boolean
  onToggle: () => void
  onCopy: (password: string) => void
}) {
  const shown = revealedPassword(network, revealed)
  return (
    <div
      className={cn("flex items-center gap-3 py-1", divided && "border-t border-border-subtle")}
    >
      <div className="min-w-0 flex-1">
        <p className="text-text-primary">{network.ssid}</p>
        <span className="flex items-center gap-1.5 text-[11.5px] text-text-tertiary">
          {network.security === null ? null : <span>{network.security}</span>}
          {shown === null ? null : (
            <span className="font-mono" data-selectable>
              {shown}
            </span>
          )}
        </span>
      </div>
      {network.password === null || network.password === "" ? null : (
        <>
          <IconButton
            icon={revealed ? <EyeOff size={13} /> : <Eye size={13} />}
            label={revealed ? "Hide" : "Reveal"}
            onClick={onToggle}
          />
          <IconButton
            icon={<Clipboard size={13} />}
            label="Copy password"
            onClick={() => {
              onCopy(network.password ?? "")
            }}
          />
        </>
      )}
    </div>
  )
}
