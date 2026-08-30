import { useState } from "react"
import { Banner, Button, TextInput } from "@/components/Controls"
import { Row, Section } from "@/components/settings/SettingsKit"
import { useAppearance } from "@/hooks/useAppearance"
import { normalizeHex } from "@/lib/appearance"
import {
  BACKGROUND_PRESETS,
  MIN_COMFORTABLE_CONTRAST,
  isLightHex,
  textContrastRatio,
} from "@/lib/background"
import { cn } from "@/lib/cn"

/**
 * Settings ▸ Appearance ▸ Background and Text — the Mac's two colour sections.
 *
 * Both are the same shape and share `ColourSection` below: presets where the
 * Mac has them, a colour well, a hex field, and a Reset that means "back to the
 * stock palette" rather than "back to a colour". The arithmetic that turns one
 * picked colour into a whole palette is `lib/background.ts`.
 */
export function BackgroundSection() {
  const { background, setBackground } = useAppearance()
  return (
    <ColourSection
      title="Background"
      label="Background colour"
      value={background}
      presets={BACKGROUND_PRESETS}
      placeholder="#0d1b2a"
      detail="Repaints every pane, card and bar; hairlines and the light/dark text treatment adapt to the colour automatically. Reset it to go back to the Theme picker."
      onChange={setBackground}
    />
  )
}

export function TextSection() {
  const { background, text, resolved, setText } = useAppearance()
  // Against what the app is actually painted, not against the stored colour:
  // with no custom background that is the theme's own root, and warning about
  // a colour the app never paints would be warning about nothing.
  const behind = background === "" ? (resolved === "dark" ? "#1a1a1a" : "#f5f6f7") : background
  const ratio = text === "" ? null : textContrastRatio(text, behind)
  return (
    <ColourSection
      title="Text"
      label="Text colour"
      value={text}
      presets={[]}
      placeholder="#ececec"
      detail="Sets the primary text colour; subtitles and muted labels are derived from it automatically."
      onChange={setText}
    >
      {ratio !== null && ratio < MIN_COMFORTABLE_CONTRAST ? (
        // A nudge, not a refusal — the Mac's wording, and its behaviour: the
        // colour is applied either way.
        <Banner tone="warn">
          This colour may be hard to read on your background — the contrast is low. It’s still
          applied.
        </Banner>
      ) : null}
    </ColourSection>
  )
}

/** The hex field, its Apply, and a Reset back to the stock palette. */
function HexRow({
  label,
  value,
  placeholder,
  onChange,
  onApply,
  onReset,
}: {
  label: string
  value: string
  placeholder: string
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
            placeholder={placeholder}
            ariaLabel={`${label} hex`}
          />
        </div>
        <Button onClick={onApply}>Apply</Button>
        <Button onClick={onReset}>Reset</Button>
      </div>
    </Row>
  )
}

/** The swatch row. Its own component so `ColourSection` stays readable. */
function Presets({
  presets,
  value,
  onPick,
}: {
  presets: readonly { value: string; label: string }[]
  value: string
  onPick: (hex: string) => void
}) {
  return (
    <Row label="Presets">
      <div className="flex flex-wrap gap-2">
        {presets.map((preset) => (
          <button
            key={preset.value}
            type="button"
            aria-label={preset.label}
            title={preset.label}
            onClick={() => {
              onPick(preset.value)
            }}
            style={{ background: preset.value }}
            className={cn("size-6 rounded-full border-2 transition", swatchBorder(preset, value))}
          />
        ))}
      </div>
    </Row>
  )
}

/**
 * A light swatch on a light surface needs an outline of its own, or it reads
 * as a hole rather than as a colour.
 */
function swatchBorder(preset: { value: string }, chosen: string): string {
  if (chosen.toLowerCase() === preset.value) return "border-text-primary"
  if (isLightHex(preset.value)) return "border-border-subtle"
  return "border-transparent hover:border-border-subtle"
}

function ColourSection({
  title,
  label,
  value,
  presets,
  placeholder,
  detail,
  onChange,
  children,
}: {
  title: string
  label: string
  /** "" means none chosen, which is what Reset goes back to. */
  value: string
  presets: readonly { value: string; label: string }[]
  placeholder: string
  detail: string
  onChange: (hex: string) => void
  children?: React.ReactNode
}) {
  const [hex, setHex] = useState(value)
  const [invalid, setInvalid] = useState(false)

  const apply = (next: string) => {
    const normalized = normalizeHex(next)
    if (normalized === null) {
      setInvalid(true)
      return
    }
    setInvalid(false)
    onChange(normalized)
  }

  return (
    <Section title={title}>
      {presets.length === 0 ? null : (
        <Presets
          presets={presets}
          value={value}
          onPick={(next) => {
            onChange(next)
            setHex(next)
            setInvalid(false)
          }}
        />
      )}

      <Row label="Colour">
        <input
          type="color"
          aria-label={label}
          value={normalizeHex(value) ?? placeholder}
          onChange={(event) => {
            onChange(event.target.value)
            setHex(event.target.value)
            setInvalid(false)
          }}
          className="h-7 w-12 cursor-pointer rounded border border-border-subtle bg-transparent"
        />
      </Row>

      <HexRow
        label={label}
        value={hex}
        placeholder={placeholder}
        onChange={(next) => {
          setHex(next)
          setInvalid(false)
        }}
        onApply={() => {
          apply(hex)
        }}
        onReset={() => {
          onChange("")
          setHex("")
          setInvalid(false)
        }}
      />

      {invalid ? <Banner tone="error">That is not a colour. Use #rgb or #rrggbb.</Banner> : null}
      {children}
      <p className="text-[11.5px] text-text-tertiary">{detail}</p>
    </Section>
  )
}
