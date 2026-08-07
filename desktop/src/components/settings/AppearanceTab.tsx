import { useState } from "react"
import { Banner, Button, TextInput } from "@/components/Controls"
import { Row, Section } from "@/components/settings/SettingsKit"
import { useAppearance } from "@/hooks/useAppearance"
import {
  ACCENT_PRESETS,
  DEFAULT_ACCENT,
  isLowContrast,
  normalizeHex,
  THEMES,
} from "@/lib/appearance"
import { cn } from "@/lib/cn"

/**
 * Settings ▸ Appearance — the Mac's Theme and Accent controls.
 *
 * Accent is offered three ways, as the Mac offers it: presets, a colour well,
 * and a hex field with Reset. Three ways because people arrive with a colour
 * in three different forms — a vague preference, a swatch, or a brand hex —
 * and making them convert is the friction.
 *
 * The window opacity, blur and grain sliders are not here: they drive
 * `WindowEffects` and a compositor-level blur that Windows and Linux each need
 * their own answer for (backlog 15).
 */
export function AppearanceTab() {
  const { theme, setTheme } = useAppearance()
  return (
    <div className="flex flex-col gap-5">
      <Section title="Theme">
        <div className="flex gap-1 rounded-md bg-bg-chrome p-1">
          {THEMES.map((option) => (
            <button
              key={option.value}
              type="button"
              onClick={() => {
                setTheme(option.value)
              }}
              aria-pressed={theme === option.value}
              className={cn(
                "flex-1 rounded px-3 py-1 text-[12.5px] transition",
                theme === option.value
                  ? "bg-bg-raised text-text-primary"
                  : "text-text-secondary hover:text-text-primary",
              )}
            >
              {option.label}
            </button>
          ))}
        </div>
      </Section>

      <AccentSection />
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

      {isLowContrast(accent, resolved) ? (
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
