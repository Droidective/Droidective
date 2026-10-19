import { RefreshCw } from "lucide-react"
import { Banner, Select } from "@/components/Controls"
import { HubColumn, HubSection, IconButton, SwitchRow } from "@/components/Hub"
import { NoDevice } from "@/components/NoDevice"
import { useDeveloperSettings, withScale, withToggle } from "@/hooks/useDeviceSettings"
import { writeDevSetting } from "@/lib/daemon"
import {
  DEV_SECTIONS,
  scaleLabel,
  scaleSelection,
  togglesFor,
  type DevSection,
} from "@/lib/devsettings"
import type { Device, DevScale } from "@/lib/wire"

/**
 * Android's Developer Options over adb — the Mac's `DeveloperSettingsView`.
 *
 * Values are read from the device on open, so the panel shows ground truth
 * rather than remembered state, and the rows come from
 * `DeveloperSettingsService`'s own table over the wire rather than a second
 * copy here. What is local is the grouping: Input, Drawing, Animations, Apps,
 * in that order, which is what the Mac's `form` lays out.
 */
export function DevSettingsPane({ device }: { device: Device | null }) {
  const serial = device?.serial ?? null
  const { settings, error, refreshing, refresh, apply } = useDeveloperSettings(serial)

  if (!device) return <NoDevice feature="dev-settings" title="Developer Settings" />

  if (settings === null) {
    return (
      <div className="flex h-full flex-col gap-3 p-5">
        {error === null ? (
          <p className="text-text-tertiary">Reading developer settings…</p>
        ) : (
          <Banner tone="error">{error.message}</Banner>
        )}
      </div>
    )
  }

  const setToggle = (id: string, on: boolean) => {
    if (serial === null) return
    apply(
      (current) => withToggle(current, id, on),
      () => writeDevSetting({ serial, id, on }),
    )
  }

  const setScale = (id: string, value: number) => {
    if (serial === null) return
    apply(
      (current) => withScale(current, id, value),
      () => writeDevSetting({ serial, id, value }),
    )
  }

  return (
    <HubColumn>
      {error === null ? null : <Banner tone="error">{error.message}</Banner>}
      {DEV_SECTIONS.map((section, index) => (
        <HubSection
          key={section.title}
          title={section.title}
          // Only the first section carries Refresh, as on the Mac: one button
          // re-reads the whole table, so four of them would be four names for
          // the same action.
          accessory={
            index === 0 ? (
              <IconButton
                icon={<RefreshCw size={13} />}
                label="Refresh from the device"
                onClick={refresh}
                disabled={refreshing}
              />
            ) : undefined
          }
        >
          <SectionBody
            section={section}
            settings={settings}
            onToggle={setToggle}
            onScale={setScale}
          />
        </HubSection>
      ))}
    </HubColumn>
  )
}

function SectionBody({
  section,
  settings,
  onToggle,
  onScale,
}: {
  section: DevSection
  settings: NonNullable<ReturnType<typeof useDeveloperSettings>["settings"]>
  onToggle: (id: string, on: boolean) => void
  onScale: (id: string, value: number) => void
}) {
  if (section.kind === "scales") {
    return (
      <>
        {settings.scales.map((scale) => (
          <ScaleRow
            key={scale.id}
            scale={scale}
            choices={settings.scaleChoices}
            onChange={(value) => {
              onScale(scale.id, value)
            }}
          />
        ))}
      </>
    )
  }
  return (
    <>
      {togglesFor(section, settings.toggles).map((toggle) => (
        <SwitchRow
          key={toggle.id}
          title={toggle.title}
          subtitle={toggle.detail}
          checked={toggle.on}
          onChange={(on) => {
            onToggle(toggle.id, on)
          }}
        />
      ))}
    </>
  )
}

/** Title on the leading edge, a compact picker trailing — the Mac's layout. */
function ScaleRow({
  scale,
  choices,
  onChange,
}: {
  scale: DevScale
  choices: number[]
  onChange: (value: number) => void
}) {
  return (
    <div className="flex items-center gap-3">
      <span className="min-w-0 flex-1 text-text-primary">{scale.title}</span>
      <div className="w-24 shrink-0">
        <Select
          value={String(scaleSelection(scale, choices))}
          options={choices.map((choice) => ({
            value: String(choice),
            label: scaleLabel(choice),
          }))}
          onChange={(value) => {
            onChange(Number(value))
          }}
        />
      </div>
    </div>
  )
}
