import { useState } from "react"
import { Button, Select, TextInput } from "@/components/Controls"
import { HubColumn, HubSection, SwitchRow } from "@/components/Hub"
import { NoDevice } from "@/components/screen"
import { useHubAction, type HubActions } from "@/hooks/useHubAction"
import { localeOptions } from "@/lib/hub-fields"
import { TOGGLE_PARAM, type Device, type FeatureSummary } from "@/lib/wire"

/**
 * The Simulate / Device State hub — the Mac's `SimulateView`, section for
 * section: battery, appearance and motion, layout, locale, network, proxy.
 *
 * Each section runs the matching registry feature through the same `run_action`
 * route a generated form uses, so nothing here re-implements an action; the
 * gathered features stay searchable and hotkey-able.
 *
 * **Two things the Mac's screen has and this does not**, both named rather than
 * quietly missing. Its push-notification section is `simctl` against an iOS
 * Simulator, which does not exist on Windows or Linux — the section is absent
 * rather than present and permanently broken, the same call the Emulators
 * screen made. And its "Reset all overrides" button reads `activeOverrides`,
 * the reconciled record of what has been overridden, which this app does not
 * keep: the two switches in Appearance therefore start off and say what they
 * will *apply* rather than what the device currently is.
 *
 * The whole screen is keyed on the device, so a half-typed density or proxy
 * cannot follow the selection to the next one — the Mac clears the same fields
 * in its `onChange`.
 */
export function SimulateHubPane({
  device,
  features,
}: {
  device: Device | null
  features: FeatureSummary[]
}) {
  const actions = useHubAction(device)

  if (!device) return <NoDevice feature="simulate" title="Simulate" />

  return (
    <HubColumn>
      <BatterySection key={`battery-${device.serial}`} actions={actions} />
      <AppearanceSection key={`appearance-${device.serial}`} actions={actions} />
      <LayoutSection key={`layout-${device.serial}`} actions={actions} />
      <LocaleSection key={`locale-${device.serial}`} actions={actions} features={features} />
      <NetworkSection actions={actions} />
      <ProxySection key={`proxy-${device.serial}`} actions={actions} />
    </HubColumn>
  )
}

function BatterySection({ actions }: { actions: HubActions }) {
  const [level, setLevel] = useState(5)
  const [unplugged, setUnplugged] = useState(true)

  return (
    <HubSection title="Battery">
      <Slider label={`Level: ${level}%`} ariaLabel="Battery level" min={0} max={100} step={1} value={level} onChange={setLevel} />
      <SwitchRow title="Simulate unplugged" checked={unplugged} onChange={setUnplugged} />
      <Apply actions={actions} featureId="fake-battery" fields={{ level, unplugged }} />
    </HubSection>
  )
}

/**
 * Dark mode and animation scale, the registry's two `toggleAction`s here.
 *
 * They apply on the flip, as the Mac's `OverrideToggleControl` does. What they
 * cannot do is *start* in the device's state: the Mac reads `activeOverrides`,
 * its reconciled record of what it has overridden, and this app keeps none — so
 * the subtitle says which of the two this is rather than letting a switch imply
 * it read the device.
 */
function AppearanceSection({ actions }: { actions: HubActions }) {
  const [dark, setDark] = useState(false)
  const [animationsOff, setAnimationsOff] = useState(false)

  return (
    <HubSection
      title="Appearance & motion"
      subtitle="Applied when flipped. This app does not read back what a device is already overriding."
    >
      <SwitchRow
        title="Dark mode"
        checked={dark}
        disabled={actions.runningId === "dark-mode"}
        onChange={(next) => {
          setDark(next)
          actions.run("dark-mode", { [TOGGLE_PARAM]: next })
        }}
      />
      <SwitchRow
        title="Disable animations (0×)"
        checked={animationsOff}
        disabled={actions.runningId === "animation-scale"}
        onChange={(next) => {
          setAnimationsOff(next)
          actions.run("animation-scale", { [TOGGLE_PARAM]: next })
        }}
      />
    </HubSection>
  )
}

function LayoutSection({ actions }: { actions: HubActions }) {
  const [fontScale, setFontScale] = useState(1)
  const [density, setDensity] = useState("")
  const dpi = Number(density.trim())

  return (
    <HubSection title="Layout">
      <Slider
        label={`Font scale: ${fontScale.toFixed(2)}`}
        ariaLabel="Font scale"
        min={0.85}
        max={1.3}
        step={0.05}
        value={fontScale}
        onChange={setFontScale}
      />
      <Field label="Display density">
        <TextInput
          value={density}
          onChange={setDensity}
          placeholder="dpi — blank to keep"
          type="number"
          ariaLabel="Display density"
        />
      </Field>
      <Apply
        actions={actions}
        featureId="layout-overrides"
        fields={{
          fontScale,
          // Blank keeps the device's own, which is why it is omitted rather
          // than sent as a zero the runner would apply.
          ...(density.trim() !== "" && Number.isFinite(dpi) ? { density: dpi } : {}),
        }}
      />
    </HubSection>
  )
}

function LocaleSection({
  actions,
  features,
}: {
  actions: HubActions
  features: FeatureSummary[]
}) {
  const [locale, setLocale] = useState("en-US")

  return (
    <HubSection title="Locale">
      <div className="flex items-center gap-3">
        <span className="text-text-primary">Language</span>
        <div className="ml-auto min-w-[160px]">
          <Select value={locale} options={localeOptions(features)} onChange={setLocale} />
        </div>
      </div>
      <Apply actions={actions} featureId="locale" fields={{ locale }} />
    </HubSection>
  )
}

/**
 * The three radios. Not keyed on the device like the others: these are the
 * state the device is *asked* for rather than something half-typed, and the
 * Mac does not reset them on a device change either.
 */
function NetworkSection({ actions }: { actions: HubActions }) {
  const [wifi, setWifi] = useState(true)
  const [data, setData] = useState(true)
  const [airplane, setAirplane] = useState(false)

  return (
    <HubSection title="Network">
      <SwitchRow title="Wi-Fi" checked={wifi} onChange={setWifi} />
      <SwitchRow title="Mobile data" checked={data} onChange={setData} />
      <SwitchRow title="Airplane mode" checked={airplane} onChange={setAirplane} />
      <Apply actions={actions} featureId="network-toggles" fields={{ wifi, data, airplane }} />
    </HubSection>
  )
}

function ProxySection({ actions }: { actions: HubActions }) {
  const [proxy, setProxy] = useState("")
  const busy = actions.runningId === "http-proxy"

  return (
    <HubSection title="HTTP proxy" subtitle="Route traffic through Charles, Proxyman, or mitmproxy.">
      <TextInput
        value={proxy}
        onChange={setProxy}
        placeholder="10.0.0.5:8888"
        ariaLabel="Proxy host and port"
      />
      <div className="flex items-center gap-2.5">
        <Button
          tone="primary"
          disabled={busy || proxy.trim() === ""}
          onClick={() => {
            actions.run("http-proxy", { proxy: proxy.trim() })
          }}
        >
          Set
        </Button>
        {/* An empty value is what clears it, so this is the same action with a
            different argument rather than a second runner. */}
        <Button
          disabled={busy}
          onClick={() => {
            actions.run("http-proxy", { proxy: "" })
          }}
        >
          Clear
        </Button>
      </div>
    </HubSection>
  )
}

/** SwiftUI's `Slider` with the value read out above it, as every section does. */
function Slider({
  label,
  ariaLabel,
  min,
  max,
  step,
  value,
  onChange,
}: {
  label: string
  ariaLabel: string
  min: number
  max: number
  step: number
  value: number
  onChange: (value: number) => void
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-text-primary">{label}</span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        aria-label={ariaLabel}
        onChange={(event) => {
          onChange(Number(event.target.value))
        }}
        className="accent-accent"
      />
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-[11.5px] text-text-tertiary">{label}</span>
      {children}
    </div>
  )
}

/** The section's own Apply, disabled only while its own action is in flight. */
function Apply({
  actions,
  featureId,
  fields,
}: {
  actions: HubActions
  featureId: string
  fields: Parameters<HubActions["run"]>[1]
}) {
  return (
    <div>
      <Button
        tone="primary"
        disabled={actions.runningId === featureId}
        onClick={() => {
          actions.run(featureId, fields)
        }}
      >
        Apply
      </Button>
    </div>
  )
}
