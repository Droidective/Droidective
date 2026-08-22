import { useState } from "react"
import { RefreshCw, Wifi, WifiOff } from "lucide-react"
import { Banner, Button, Select, Switch, TextInput } from "@/components/Controls"
import { IconButton } from "@/components/Hub"
import { NoDevice } from "@/components/screen"
import { WifiSaved } from "@/components/WifiSaved"
import { useWifi } from "@/hooks/useWifi"
import { canConnect, SECURITY_MODES, wifiDetail, wifiHeadline } from "@/lib/network"
import type { Device } from "@/lib/wire"

/**
 * Wi-Fi control — the Mac's `WiFiView`.
 *
 * Three cards down a 620-wide column: the current connection with the radio
 * toggle and a refresh, a connect form, and the saved networks with their
 * passwords revealed and copyable on a rooted device.
 */
export function WifiPane({ device }: { device: Device | null }) {
  const { data, error, loaded, busy, refresh, setEnabled, connect, copyPassword } = useWifi(
    device?.serial ?? null,
  )
  const [ssid, setSsid] = useState("")
  const [security, setSecurity] = useState("wpa2")
  const [password, setPassword] = useState("")

  if (!device) return <NoDevice feature="wifi" title="Wi-Fi" />

  const status = data?.status ?? null
  const connected = status?.connected ?? false
  const detail = wifiDetail(status)

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <div className="mx-auto flex w-full max-w-[620px] flex-col gap-[18px] p-4">
        {error === null ? null : <Banner tone="error">{error.message}</Banner>}

        <section className="flex items-center gap-3 rounded-[10px] bg-bg-surface p-3.5">
          {connected ? (
            <Wifi size={26} className="shrink-0 text-accent" />
          ) : (
            <WifiOff size={26} className="shrink-0 text-text-tertiary" />
          )}
          <div className="min-w-0 flex-1">
            <h2 className="text-[15px] font-bold text-text-primary">{wifiHeadline(status)}</h2>
            {detail === "" ? null : <p className="text-text-tertiary">{detail}</p>}
          </div>
          <IconButton
            icon={<RefreshCw size={13} />}
            label="Refresh"
            onClick={refresh}
            disabled={busy}
          />
          <Switch
            checked={status?.enabled ?? false}
            onChange={setEnabled}
            ariaLabel="Wi-Fi"
          />
        </section>

        <section className="flex flex-col gap-2 rounded-[10px] bg-bg-surface p-3.5">
          <h2 className="text-[13px] font-semibold text-text-primary">Connect to a network</h2>
          <div className="flex gap-2">
            <TextInput value={ssid} onChange={setSsid} placeholder="SSID" />
            <div className="w-[104px] shrink-0">
              <Select value={security} options={[...SECURITY_MODES]} onChange={setSecurity} />
            </div>
          </div>
          <TextInput
            value={password}
            onChange={setPassword}
            placeholder="Password (blank for open)"
            type="password"
          />
          <div className="flex items-center gap-3">
            <p className="min-w-0 flex-1 text-[11.5px] text-text-tertiary">
              <code>cmd wifi connect-network</code> (Android 11+); some ROMs block it over adb.
            </p>
            <Button
              onClick={() => {
                connect(ssid, security, password)
                setPassword("")
              }}
              disabled={!canConnect(ssid, busy)}
            >
              Connect
            </Button>
          </div>
        </section>

        <WifiSaved
          networks={data?.networks ?? []}
          hasRoot={data?.hasRootShell ?? false}
          loaded={loaded}
          onCopy={copyPassword}
        />
      </div>
    </div>
  )
}
