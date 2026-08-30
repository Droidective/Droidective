import { useState } from "react"
import { Banner, Button, Switch, TextInput } from "@/components/Controls"
import { BackgroundSection, TextSection } from "@/components/settings/AppearanceColors"
import { Row, Section } from "@/components/settings/SettingsKit"
import { useAppearance } from "@/hooks/useAppearance"
import {
  ACCENT_PRESETS,
  accentFor,
  DEFAULT_ACCENT,
  isLowContrast,
  normalizeHex,
  THEMES,
} from "@/lib/appearance"
import { cn } from "@/lib/cn"
import { ZOOM_STEPS, zoomLabel } from "@/lib/zoom"

/**
 * Settings ▸ Appearance — the Mac's Theme and Accent controls.
 *
 * Accent is offered three ways, as the Mac offers it: presets, a colour well,
 * and a hex field with Reset. Three ways because people arrive with a colour
 * in three different forms — a vague preference, a swatch, or a brand hex —
 * and making them convert is the friction.
 *
 * The Window section carries the sidebar mode and the UI size — the same two
 * the Mac keeps there — and says outright that opacity, blur and grain are not
 * ported, since blur is a compositor-level effect Windows and Linux each need
 * their own answer for (backlog 15).
 */
export interface AppearanceTabProps {
  sidebarAutoHide: boolean
  onSidebarAutoHide: (autoHide: boolean) => void
  zoomStep: number
  onZoom: (direction: -1 | 0 | 1) => void
}

export function AppearanceTab(props: AppearanceTabProps) {
  const { theme, background, setTheme } = useAppearance()
  const overridden = background !== ""
  return (
    <div className="flex flex-col gap-5">
      <Section title="Theme">
        <div className="flex gap-1 rounded-md bg-bg-chrome p-1">
          {THEMES.map((option) => (
            <button
              key={option.value}
              type="button"
              disabled={overridden}
              onClick={() => {
                setTheme(option.value)
              }}
              aria-pressed={theme === option.value}
              className={cn(
                "flex-1 rounded px-3 py-1 text-[12.5px] transition disabled:opacity-40",
                theme === option.value
                  ? "bg-bg-raised text-text-primary"
                  : "text-text-secondary hover:text-text-primary",
              )}
            >
              {option.label}
            </button>
          ))}
        </div>
        {overridden ? (
          <p className="text-[11.5px] text-text-tertiary">
            Overridden by your custom background below — light/dark follows that colour. Reset the
            background to use the theme.
          </p>
        ) : null}
      </Section>

      <AccentSection />
      <BackgroundSection />
      <TextSection />

      <Section title="Window">
        <Row
          label="Auto-hide the sidebar"
          detail="Dock-style: hover the window's left edge to peek, or Ctrl/⌘ + B."
        >
          <Switch
            checked={props.sidebarAutoHide}
            onChange={props.onSidebarAutoHide}
            ariaLabel="Auto-hide the sidebar"
          />
        </Row>
        <Row
          label="UI size"
          detail="Ctrl/⌘ + = and Ctrl/⌘ + − step it; Ctrl/⌘ + 0 is Actual Size."
        >
          <ZoomControl step={props.zoomStep} onZoom={props.onZoom} />
        </Row>
        <Row
          label="Opacity, blur and grain"
          detail="The Mac's translucent window. Blur needs a per-platform answer (Mica on Windows, a compositor effect on Linux) — backlog 15."
        >
          <span className="text-[11.5px] text-text-tertiary">Not yet</span>
        </Row>
      </Section>
    </div>
  )
}

/** Minus, the current percentage, plus — the same steps ⌘=/⌘- walk. */
function ZoomControl({
  step,
  onZoom,
}: {
  step: number
  onZoom: (direction: -1 | 0 | 1) => void
}) {
  return (
    <div className="flex items-center gap-1.5">
      <Button
        onClick={() => {
          onZoom(-1)
        }}
        disabled={step === 0}
        title="Zoom out"
      >
        −
      </Button>
      <button
        type="button"
        onClick={() => {
          onZoom(0)
        }}
        title="Actual Size"
        className="w-12 text-center tabular-nums text-text-secondary hover:text-text-primary"
      >
        {zoomLabel(step)}
      </button>
      <Button
        onClick={() => {
          onZoom(1)
        }}
        disabled={step === ZOOM_STEPS.length - 1}
        title="Zoom in"
      >
        +
      </Button>
    </div>
  )
}

function AccentSection() {
  const { accent, resolved, setAccent } = useAppearance()
  const [hex, setHex] = useState(accent)
  const [invalid, setInvalid] = useState(false)

  const apply = (value: string) => {
    const normalized = normalizeHex(value)
    if (normalized === null) {
      setInvalid(true)
      return
    }
    setInvalid(false)
    setAccent(normalized)
  }

  return (
    <Section title="Accent">
      <Row label="Presets">
        <div className="flex flex-wrap gap-2">
          {ACCENT_PRESETS.map((preset) => (
            <button
              key={preset.value}
              type="button"
              aria-label={preset.label}
              title={preset.label}
              onClick={() => {
                setAccent(preset.value)
                setHex(preset.value)
                setInvalid(false)
              }}
              style={{ background: preset.value }}
              className={cn(
                "size-6 rounded-full border-2 transition",
                accent.toLowerCase() === preset.value
                  ? "border-text-primary"
                  : "border-transparent hover:border-border-subtle",
              )}
            />
          ))}
        </div>
      </Row>

      <Row label="Colour">
        <input
          type="color"
          aria-label="Accent colour"
          value={normalizeHex(accent) ?? DEFAULT_ACCENT}
          onChange={(event) => {
            setAccent(event.target.value)
            setHex(event.target.value)
            setInvalid(false)
          }}
          className="h-7 w-12 cursor-pointer rounded border border-border-subtle bg-transparent"
        />
      </Row>

      <HexRow
        value={hex}
        onChange={(next) => {
          setHex(next)
          setInvalid(false)
        }}
        onApply={() => {
          apply(hex)
        }}
        onReset={() => {
          setAccent(DEFAULT_ACCENT)
          setHex(DEFAULT_ACCENT)
          setInvalid(false)
        }}
      />

      {invalid ? <Banner tone="error">That is not a colour. Use #rgb or #rrggbb.</Banner> : null}

      {/* The *applied* accent, not the stored one: light mode darkens the
          default green, and warning about a colour the app never paints would
          fire on its own default. */}
      {isLowContrast(accentFor(accent, resolved), resolved) ? (
        // A warning, not a refusal: it is the user's app, and the Mac says
        // the same thing rather than rejecting the colour.
        <Banner tone="warn">This accent is hard to read against the {resolved} background.</Banner>
      ) : null}
    </Section>
  )
}

/** The hex field, its Apply, and the Reset back to the brand green. */
function HexRow({
  value,
  onChange,
  onApply,
  onReset,
}: {
  value: string
  onChange: (value: string) => void
  onApply: () => void
  onReset: () => void
}) {
  return (
    <Row label="Hex">
      <div className="flex items-center gap-2">
        <div className="w-[110px]">
          <TextInput
            value={value}
            onChange={onChange}
            onKeyDown={(event) => {
              if (event.key === "Enter") onApply()
            }}
            placeholder={DEFAULT_ACCENT}
            ariaLabel="Accent hex"
          />
        </div>
        <Button onClick={onApply}>Apply</Button>
        <Button onClick={onReset}>Reset</Button>
      </div>
    </Row>
  )
}
