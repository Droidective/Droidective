import type { ReactNode } from "react"
import type { DrawSettings } from "@/lib/screenshot-editor"
import { PALETTE, type Annotation } from "@/lib/screenshot-markup"

/**
 * The toolbar's controls.
 *
 * Split from `ScreenshotToolbar` so that file stays a row of buttons rather
 * than a row of buttons plus four widgets.
 */

export interface RedactProps {
  settings: DrawSettings
  onSettings: (settings: DrawSettings) => void
  selected: Annotation | null
  onReplaceSelected: (annotation: Annotation, recordUndo: boolean) => void
}

export function Swatches({
  settings,
  onSettings,
}: {
  settings: DrawSettings
  onSettings: (settings: DrawSettings) => void
}) {
  return (
    <div className="flex items-center gap-1">
      {PALETTE.map((swatch) => (
        <button
          key={swatch}
          type="button"
          aria-label={`Colour ${swatch}`}
          aria-pressed={settings.color === swatch}
          onClick={() => {
            onSettings({ ...settings, color: swatch })
          }}
          className={
            settings.color === swatch
              ? "size-4 rounded-full ring-2 ring-accent ring-offset-2 ring-offset-bg-chrome"
              : "size-4 rounded-full ring-1 ring-border-subtle"
          }
          style={{ background: swatch }}
        />
      ))}
      <input
        type="color"
        aria-label="Custom colour"
        title="Custom colour"
        value={settings.color}
        onChange={(event) => {
          onSettings({ ...settings, color: event.target.value })
        }}
        className="ml-1 size-5 cursor-pointer rounded-full border-0 bg-transparent p-0"
      />
    </div>
  )
}

/**
 * The redaction's style and its one slider.
 *
 * Both edit the *picked* redaction when there is one and the default for new
 * ones otherwise, which is how the Mac's work — changing a region's blur after
 * drawing it is the common case, and a slider that only affected the next one
 * would read as broken.
 */
export function RedactControls({
  settings,
  onSettings,
  selected,
  onReplaceSelected,
}: RedactProps) {
  const subject = selected?.tool === "redact" ? selected : null
  const style = subject?.redactStyle ?? settings.redactStyle
  const value =
    style === "blur"
      ? (subject?.blurStrength ?? settings.blurStrength)
      : (subject?.fillOpacity ?? settings.fillOpacity)

  const setStyle = (next: "blur" | "solid") => {
    if (subject === null) onSettings({ ...settings, redactStyle: next })
    else onReplaceSelected({ ...subject, redactStyle: next }, true)
  }
  const setAmount = (next: number) => {
    if (subject === null) {
      onSettings(
        style === "blur" ? { ...settings, blurStrength: next } : { ...settings, fillOpacity: next },
      )
      return
    }
    onReplaceSelected(
      style === "blur" ? { ...subject, blurStrength: next } : { ...subject, fillOpacity: next },
      false,
    )
  }

  return (
    <div className="flex items-center gap-2">
      <ToolbarSelect
        label="Redaction style"
        value={style}
        onChange={(next) => {
          setStyle(next === "blur" ? "blur" : "solid")
        }}
        options={[
          { value: "blur", label: "Blur" },
          { value: "solid", label: "Solid" },
        ]}
      />
      <input
        type="range"
        aria-label={style === "blur" ? "Blur amount" : "Fill opacity"}
        title={style === "blur" ? "Blur amount" : "Fill opacity"}
        min={style === "blur" ? 0 : 0.1}
        max={1}
        step={0.05}
        value={value}
        onChange={(event) => {
          setAmount(Number(event.target.value))
        }}
        className="w-[88px] accent-accent"
      />
    </div>
  )
}

/** A compact `<select>` for the toolbar — the shared one is full-width. */
export function ToolbarSelect({
  label,
  value,
  options,
  onChange,
}: {
  label: string
  value: string
  options: { value: string; label: string }[]
  onChange: (value: string) => void
}) {
  return (
    <select
      aria-label={label}
      title={label}
      value={value}
      onChange={(event) => {
        onChange(event.target.value)
      }}
      className="rounded-md border border-border-subtle bg-bg-root px-2 py-1 text-[12px] text-text-primary outline-none focus:border-accent"
    >
      {options.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </select>
  )
}

export function Divider() {
  return <div className="h-5 w-px bg-border-subtle" />
}

export function Toggle({
  on,
  icon,
  label,
  onClick,
}: {
  on: boolean
  icon: ReactNode
  label: string
  onClick: () => void
}) {
  return (
    <button
      type="button"
      aria-label={label}
      aria-pressed={on}
      title={label}
      onClick={onClick}
      className={
        on
          ? "shrink-0 rounded-md bg-accent/[0.18] p-1.5 text-accent"
          : "shrink-0 rounded-md p-1.5 text-text-secondary transition hover:bg-white/[0.06] hover:text-text-primary"
      }
    >
      {icon}
    </button>
  )
}
