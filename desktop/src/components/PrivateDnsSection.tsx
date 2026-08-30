import { useCallback, useEffect, useState } from "react"
import { RefreshCw } from "lucide-react"
import { Banner, Button, TextInput } from "@/components/Controls"
import { HubSection, IconButton } from "@/components/Hub"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, privateDns, setPrivateDns } from "@/lib/daemon"
import { canApplyDns, DNS_MODES } from "@/lib/network"
import { cn } from "@/lib/cn"
import type { DaemonError, DnsMode } from "@/lib/wire"

/**
 * Private DNS (DNS-over-TLS) — the Mac's `PrivateDnsSection`.
 *
 * A segmented Off / Automatic / Hostname control, a provider field that
 * appears only in hostname mode, and Apply beside a refresh. Applying re-reads
 * the device afterwards, as the Mac does: the setting is what the device says
 * it is, not what was just sent.
 *
 * A section rather than a screen for the Mac's own reason — `PrivateDnsView` is
 * `HubColumn { PrivateDnsSection() }` and the Connection hub embeds the same
 * one.
 */
export function PrivateDnsSection({ serial }: { serial: string | null }) {
  const { show } = useNotifications()
  const [mode, setMode] = useState<DnsMode>("automatic")
  const [hostname, setHostname] = useState("")
  const [loaded, setLoaded] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<DaemonError | null>(null)

  const load = useCallback(async () => {
    if (serial === null) return
    setLoaded(false)
    setError(null)
    try {
      const status = await privateDns(serial)
      setMode(status.mode)
      // Kept when the device has one even in another mode, so switching to
      // Hostname does not lose what was configured.
      if (status.hostname !== null) setHostname(status.hostname)
      setLoaded(true)
    } catch (thrown) {
      setError(asDaemonError(thrown))
    }
  }, [serial])

  useEffect(() => {
    void load()
  }, [load])

  const apply = () => {
    if (serial === null) return
    setBusy(true)
    void (async () => {
      try {
        const result = await setPrivateDns({ serial, mode, hostname: hostname.trim() })
        show({ ok: result.ok, message: result.message })
      } catch (thrown) {
        show({ ok: false, message: asDaemonError(thrown).message })
      } finally {
        setBusy(false)
        await load()
      }
    })()
  }

  return (
    <>
      {error === null ? null : <Banner tone="error">{error.message}</Banner>}
      <HubSection
        title="Private DNS"
        subtitle="Set DNS-over-TLS mode for this device."
        accessory={
          <IconButton
            icon={<RefreshCw size={13} />}
            label="Refresh"
            onClick={() => {
              void load()
            }}
            disabled={busy}
          />
        }
      >
        <Segmented value={mode} onChange={setMode} />

        {mode === "hostname" ? (
          <div className="flex flex-col gap-1.5">
            <span className="text-[11.5px] text-text-tertiary">Provider hostname</span>
            <TextInput
              value={hostname}
              onChange={setHostname}
              placeholder="dns.google"
              ariaLabel="Provider hostname"
            />
          </div>
        ) : null}

        <div className="flex items-center gap-2.5">
          <Button
            tone="primary"
            onClick={apply}
            disabled={!canApplyDns(mode, hostname, loaded && !busy)}
          >
            Apply
          </Button>
          {busy ? <span className="text-text-tertiary">Applying…</span> : null}
        </div>
      </HubSection>
    </>
  )
}

/**
 * SwiftUI's `.pickerStyle(.segmented)`, which has no HTML equivalent.
 *
 * Real radio inputs under the labels rather than buttons with `role="radio"`:
 * the arrow-key behaviour, the group semantics and the form association all
 * come free, and none of them are worth reimplementing to save a hidden input.
 */
function Segmented({ value, onChange }: { value: DnsMode; onChange: (mode: DnsMode) => void }) {
  return (
    <fieldset className="flex gap-1 rounded-md bg-bg-root p-1">
      <legend className="sr-only">Private DNS mode</legend>
      {DNS_MODES.map((option) => (
        <label
          key={option.value}
          className={cn(
            "flex-1 cursor-pointer rounded px-3 py-1 text-center text-[12.5px] transition",
            value === option.value
              ? "bg-bg-raised text-text-primary"
              : "text-text-secondary hover:text-text-primary",
          )}
        >
          <input
            type="radio"
            name="private-dns-mode"
            className="sr-only"
            checked={value === option.value}
            onChange={() => {
              onChange(option.value)
            }}
          />
          {option.label}
        </label>
      ))}
    </fieldset>
  )
}
