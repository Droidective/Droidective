import type { ReactNode } from "react"
import { Check } from "lucide-react"
import { Button } from "@/components/Controls"
import { EndpointField } from "@/components/EndpointField"
import type { WirelessActions } from "@/hooks/useWirelessActions"
import { cn } from "@/lib/cn"
import { looksLikeEndpoint, looksLikePairEndpoint } from "@/lib/endpoint"

/**
 * The pairing tab's three numbered steps — the Mac's `pairTab` and its
 * `StepRow`.
 *
 * Its own file because the sheet next door is already the three tabs plus the
 * status line, and this is the only tab with a shape of its own.
 */
export function WirelessSteps({ actions }: { actions: WirelessActions }) {
  const canPair =
    !actions.busy && looksLikePairEndpoint(actions.pairEndpoint) && actions.pairCode.trim() !== ""
  const canConnect = !actions.busy && looksLikeEndpoint(actions.connectAfterPair)

  return (
    <div className="flex flex-col gap-3.5">
      <Step number={1} title="Open pairing on the device">
        <p className="text-[12px] text-text-secondary">
          Settings ▸ Developer options ▸ <strong className="font-medium">Wireless debugging</strong>{" "}
          ▸ <strong className="font-medium">Pair device with pairing code</strong>.
        </p>
      </Step>

      <Step number={2} title="Enter what the pairing dialog shows">
        <div className="flex items-end gap-3">
          <EndpointField
            label="IP address & pairing port"
            value={actions.pairEndpoint}
            placeholder="192.168.1.42:37123"
            onChange={actions.setPairEndpoint}
            onSubmit={canPair ? actions.pair : undefined}
          />
          <div className="w-[104px] shrink-0">
            <EndpointField
              label="Pairing code"
              value={actions.pairCode}
              placeholder="123456"
              onChange={actions.setPairCode}
              onSubmit={canPair ? actions.pair : undefined}
            />
          </div>
          <Button tone="primary" disabled={!canPair} onClick={actions.pair}>
            Pair
          </Button>
        </div>
      </Step>

      <Step number={3} title="Connect" done={actions.paired}>
        <p className="text-[12px] text-text-secondary">
          After pairing, Droidective looks up the connect port and connects by itself. If it
          can&rsquo;t, use the port on the main Wireless debugging screen — it differs from the
          pairing port.
        </p>
        <div className="flex items-end gap-3">
          <EndpointField
            label="IP address & port"
            value={actions.connectAfterPair}
            placeholder="192.168.1.42:40913"
            onChange={actions.setConnectAfterPair}
            onSubmit={
              canConnect
                ? () => {
                    actions.connect(actions.connectAfterPair)
                  }
                : undefined
            }
          />
          <Button
            tone="primary"
            disabled={!canConnect}
            onClick={() => {
              actions.connect(actions.connectAfterPair)
            }}
          >
            Connect
          </Button>
        </div>
      </Step>
    </div>
  )
}

/** An accent-tinted circled number — a checkmark once the step is done. */
function Step({
  number,
  title,
  done = false,
  children,
}: {
  number: number
  title: string
  done?: boolean
  children: ReactNode
}) {
  return (
    <section className="flex items-start gap-2.5">
      <span
        className={cn(
          "mt-px flex h-[19px] w-[19px] shrink-0 items-center justify-center rounded-full",
          "text-[11px] font-medium tabular-nums",
          done ? "bg-accent text-accent-fg" : "bg-accent/15 text-accent",
        )}
      >
        {done ? <Check size={12} /> : number}
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <h3 className="text-[13px] font-medium text-text-primary">{title}</h3>
        {children}
      </div>
    </section>
  )
}
