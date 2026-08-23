import { AlertTriangle, Lightbulb, Link2, RadioTower } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import type { RelayState } from "@/hooks/useReactotron"
import type { ReactotronReverseResponse } from "@/lib/wire"

const SNIPPET = `// App entry (e.g. index.js)
import Reactotron from 'reactotron-react-native'

Reactotron.configure()
  .useReactNative()
  .connect()`

/**
 * What the screen says before an app has connected — the Mac's
 * `ReactotronOnboarding`, and the place the `adb reverse` button lives.
 *
 * A relay listening with nothing attached looks exactly like a broken feature,
 * so this states which of the two it is, and puts the one action that usually
 * fixes it in reach. The tunnel is separate from the relay on purpose: the relay
 * listens on this machine whatever is plugged in, and *which* devices should be
 * able to find it is a choice.
 */
export function ReactotronWaiting({
  relay,
  port,
  error,
  hasDevice,
  tunnel,
  failure,
  onReverse,
  onRestart,
}: {
  relay: RelayState
  port: number | null
  error: string | null
  hasDevice: boolean
  /** The last tunnel attempt, so its per-device outcome stays on screen. */
  tunnel: ReactotronReverseResponse | null
  /** A tunnel request that never reached adb at all. */
  failure: string | null
  onReverse: () => void
  onRestart: () => void
}) {
  if (relay === "failed") {
    return (
      <Centred>
        <AlertTriangle size={34} className="text-danger" />
        <h2 className="text-[15px] font-semibold">The Reactotron relay stopped</h2>
        <p className="max-w-[460px] text-center text-text-secondary" data-selectable>
          {error ??
            "The relay is no longer listening. Another Reactotron may have taken port 9090 — close it, then start this one again."}
        </p>
        <Button tone="primary" onClick={onRestart}>
          Start the relay again
        </Button>
      </Centred>
    )
  }

  return (
    <Centred>
      <RadioTower size={34} className="text-text-tertiary" />
      <h2 className="text-[15px] font-semibold">
        {relay === "starting" ? "Starting the relay…" : "Waiting for your app"}
      </h2>
      <p className="max-w-[460px] text-center text-text-secondary">
        Droidective is the Reactotron server — it is listening on{" "}
        <span className="font-mono text-text-primary">:{port ?? 9090}</span>. Add the client to your
        app and reload:
      </p>
      <pre
        className="rounded-md bg-bg-surface px-3 py-2.5 font-mono text-[11px] leading-[1.6] text-text-primary"
        data-selectable
      >
        {SNIPPET}
      </pre>
      <p className="text-[11.5px] text-text-tertiary">
        Needs <span className="font-mono">reactotron-react-native</span> installed in the app, and a
        dev build.
      </p>

      <Tunnel
        hasDevice={hasDevice}
        tunnel={tunnel}
        failure={failure}
        onReverse={onReverse}
      />
      <AlreadyRunning />
    </Centred>
  )
}

/**
 * The tunnel card.
 *
 * A device reaches the relay through its *own* localhost, which only works once
 * `adb reverse` is open — and nothing about a missing tunnel is visible from
 * inside the app, so this says it out loud rather than waiting to be discovered.
 */
function Tunnel({
  hasDevice,
  tunnel,
  failure,
  onReverse,
}: {
  hasDevice: boolean
  tunnel: ReactotronReverseResponse | null
  failure: string | null
  onReverse: () => void
}) {
  const failures = tunnel?.results.filter((result) => !result.ok) ?? []
  return (
    <Card
      icon={<Link2 size={13} className="text-rt-key" />}
      tint="bg-rt-key/15"
      title="Device on USB or an emulator?"
      body={
        hasDevice
          ? "It reaches the relay through its own localhost, which needs a reverse tunnel."
          : "Connect one and this opens the reverse tunnel it needs."
      }
      action={
        <Button onClick={onReverse} disabled={!hasDevice} title="adb reverse tcp:9090 tcp:9090">
          Open tunnel
        </Button>
      }
    >
      {failure === null ? null : (
        <div className="pt-2">
          <Banner tone="error">{failure}</Banner>
        </div>
      )}
      {tunnel === null ? null : (
        <div className="flex flex-col gap-1.5 pt-2">
          <code className="text-[11px] text-text-tertiary" data-selectable>
            {tunnel.command}
          </code>
          {failures.length === 0 ? (
            <Banner tone="ok">
              Tunnel open on {tunnel.results.length === 1 ? "the device" : `${tunnel.results.length} devices`}. Reload
              your app so it reconnects.
            </Banner>
          ) : (
            failures.map((result) => (
              <Banner key={result.serial} tone="error">
                {result.serial}: {result.detail === "" ? "adb refused the tunnel" : result.detail}
              </Banner>
            ))
          )}
        </div>
      )}
    </Card>
  )
}

/**
 * A client only registers when it launches, so an app that was already open
 * before the relay came up will not appear until it restarts. The Mac carries
 * the same hint, with the same reason.
 */
function AlreadyRunning() {
  return (
    <Card
      icon={<Lightbulb size={13} className="text-rt-name" />}
      tint="bg-rt-name/15"
      title="Already running your app?"
      body="Restart it so it reconnects — a client only introduces itself on launch."
    />
  )
}

function Card({
  icon,
  tint,
  title,
  body,
  action,
  children,
}: {
  icon: React.ReactNode
  tint: string
  title: string
  body: string
  action?: React.ReactNode
  children?: React.ReactNode
}) {
  return (
    <div className="w-full max-w-[460px] rounded-xl border border-border-subtle bg-bg-surface px-3.5 py-3">
      <div className="flex items-center gap-3">
        <span className={`flex size-[30px] shrink-0 items-center justify-center rounded-full ${tint}`}>
          {icon}
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-[12px] font-semibold text-text-primary">{title}</p>
          <p className="text-[11.5px] text-text-secondary">{body}</p>
        </div>
        {action}
      </div>
      {children}
    </div>
  )
}

function Centred({ children }: { children: React.ReactNode }) {
  // `flex-1` with both maxes at infinity, or the whole column centres inside a
  // shrink-wrapped box and the content floats above the middle of the pane.
  return (
    <div className="flex min-h-0 flex-1 flex-col items-center justify-center gap-3.5 overflow-y-auto p-8">
      {children}
    </div>
  )
}
