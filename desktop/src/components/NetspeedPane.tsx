import { useState } from "react"
import { Banner } from "@/components/Controls"
import { NetspeedCharts } from "@/components/NetspeedCharts"
import { NetspeedToolbar } from "@/components/NetspeedToolbar"
import { ConfirmDialog, NoDevice } from "@/components/screen"
import { useNetspeed } from "@/hooks/useNetspeed"
import { writeRecording } from "@/lib/netexport"
import { chartMax, sessionTotals } from "@/lib/netspeed"
import { useNotifications } from "@/hooks/useNotifications"
import type { Device } from "@/lib/wire"

/**
 * Live download and upload throughput — the Mac's `NetworkView`.
 *
 * Sampling starts the moment the screen opens, because watching traffic is
 * what this is for; Record is a second, explicit state that keeps those
 * samples for export. Stopping a recording with something in it asks first, as
 * the Mac's exit guard does, since an unexported recording is the one thing
 * this screen can lose.
 */
export function NetspeedPane({ device }: { device: Device | null }) {
  const { show } = useNotifications()
  const net = useNetspeed(device?.serial ?? null)
  const [confirming, setConfirming] = useState(false)

  if (!device) return <NoDevice feature="network-speed" title="Network Speed" />

  const latest = net.live.at(-1) ?? null
  const totals = sessionTotals(net.live)
  const max = chartMax(net.live)

  // Writes and returns, as the Mac's `NetworkView.export()` does. It must not
  // touch the recording: exporting is not a way of ending one, and a recording
  // you have saved once is still there to save again.
  const exportRecording = () => {
    writeRecording(net.recorded, device.serial).then(show, ignore)
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <NetspeedToolbar
        net={net}
        latest={latest}
        onExport={exportRecording}
        onStop={() => {
          if (net.recorded.length === 0) {
            net.stopRecording()
            return
          }
          setConfirming(true)
        }}
      />

      {confirming ? (
        <ConfirmDialog
          title="Export this recording before stopping?"
          message={`${String(net.recorded.length)} samples captured — exported as JSON + CSV.`}
          confirmLabel="Stop without exporting"
          extraLabel="Export…"
          onExtra={() => {
            setConfirming(false)
            exportRecording()
            net.stopRecording()
          }}
          onConfirm={() => {
            // "not now", not "throw it away" — the samples stay exportable,
            // which is what `PerformancePane` does with the same dialog.
            setConfirming(false)
            net.stopRecording()
          }}
          onCancel={() => {
            setConfirming(false)
          }}
        />
      ) : null}

      <Notices error={net.error} dropped={net.dropped} />

      {net.live.length === 0 ? (
        <p className="flex min-h-0 flex-1 items-center justify-center px-8 text-center text-text-tertiary">
          Waiting for the first sample. Throughput is the difference between two reads, so it takes
          a second to appear.
        </p>
      ) : (
        <NetspeedCharts live={net.live} latest={latest} totals={totals} max={max} />
      )}
    </div>
  )
}

/** `writeRecording` reports through the toast; it never rejects. */
function ignore() {}

/** The stream's own states — what is about the stream, not about an action. */
function Notices({ error, dropped }: { error: { message: string } | null; dropped: number }) {
  if (error === null && dropped === 0) return null
  return (
    <div className="flex shrink-0 flex-col gap-2 px-3 pt-3">
      {error === null ? null : <Banner tone="error">{error.message}</Banner>}
      {dropped === 0 ? null : (
        <Banner tone="warn">{dropped} samples were dropped — the charts have a gap.</Banner>
      )}
    </div>
  )
}
