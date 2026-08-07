import type { ReactNode } from "react"
import { cn } from "@/lib/cn"

/**
 * The handful of form primitives this app needs, on the Mac app's palette.
 *
 * Hand-written rather than pulled from a component library: three controls do
 * not justify the dependency, and the tokens they use are the ones ported from
 * the native app's theme. Worth revisiting when the surface grows.
 */

type ButtonTone = "default" | "primary" | "danger"

export function Button({
  children,
  onClick,
  tone = "default",
  disabled = false,
  title,
}: {
  children: ReactNode
  onClick?: () => void
  tone?: ButtonTone
  disabled?: boolean
  // Explicitly `| undefined`: with exactOptionalPropertyTypes, passing a
  // computed `string | undefined` to a bare optional prop is a type error.
  title?: string | undefined
}) {
  const tones: Record<ButtonTone, string> = {
    default: "bg-bg-raised hover:bg-border-subtle text-text-primary",
    primary: "bg-accent hover:brightness-110 text-accent-fg font-medium",
    danger: "bg-danger hover:brightness-110 text-white font-medium",
  }
  return (
    <button
      type="button"
      title={title}
      onClick={onClick}
      disabled={disabled}
      className={cn(
        "rounded-md px-3 py-1.5 text-[13px] transition",
        "disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:brightness-100",
        tones[tone],
      )}
    >
      {children}
    </button>
  )
}

export function TextInput({
  value,
  onChange,
  placeholder,
  type = "text",
  autoFocus = false,
  onKeyDown,
  ariaLabel,
}: {
  value: string
  onChange: (value: string) => void
  placeholder?: string | undefined
  /** `password` is SwiftUI's `SecureField` — the Wi-Fi form uses it. */
  type?: "text" | "number" | "password"
  autoFocus?: boolean
  onKeyDown?: (event: React.KeyboardEvent<HTMLInputElement>) => void
  /** A placeholder is not a name: it is gone the moment anything is typed. */
  ariaLabel?: string | undefined
}) {
  return (
    <input
      type={type}
      value={value}
      placeholder={placeholder}
      aria-label={ariaLabel ?? placeholder}
      // Only the palette's search field asks for this, and it is the app's
      // entry point; landing anywhere else costs a keystroke every launch.
      // oxlint-disable-next-line jsx-a11y/no-autofocus
      autoFocus={autoFocus}
      onChange={(event) => {
        onChange(event.target.value)
      }}
      onKeyDown={onKeyDown}
      className={cn(
        "w-full rounded-md border border-border-subtle bg-bg-root px-2.5 py-1.5",
        "text-[13px] text-text-primary placeholder:text-text-tertiary",
        "outline-none focus:border-accent",
      )}
    />
  )
}

export function Select({
  value,
  options,
  onChange,
}: {
  value: string
  options: { value: string; label: string }[]
  onChange: (value: string) => void
}) {
  return (
    <select
      value={value}
      onChange={(event) => {
        onChange(event.target.value)
      }}
      className={cn(
        "w-full rounded-md border border-border-subtle bg-bg-root px-2 py-1.5",
        "text-[13px] text-text-primary outline-none focus:border-accent",
      )}
    >
      {options.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </select>
  )
}

export function Switch({
  checked,
  onChange,
  label,
  ariaLabel,
}: {
  checked: boolean
  onChange: (checked: boolean) => void
  label?: string | undefined
  /** For a switch whose only caption is a separate field label. */
  ariaLabel?: string | undefined
}) {
  return (
    <label className="flex cursor-pointer items-center gap-2">
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label ?? ariaLabel ?? "Toggle"}
        onClick={() => {
          onChange(!checked)
        }}
        className={cn(
          "relative h-[18px] w-8 shrink-0 rounded-full transition",
          checked ? "bg-accent" : "bg-border-subtle",
        )}
      >
        <span
          className={cn(
            "absolute top-0.5 h-3.5 w-3.5 rounded-full bg-white transition-all",
            checked ? "left-[17px]" : "left-0.5",
          )}
        />
      </button>
      {label ? <span className="text-text-secondary">{label}</span> : null}
    </label>
  )
}

export function Slider({
  value,
  min,
  max,
  step,
  onChange,
}: {
  value: number
  min: number
  max: number
  step: number
  onChange: (value: number) => void
}) {
  return (
    <div className="flex items-center gap-3">
      <input
        type="range"
        value={value}
        min={min}
        max={max}
        step={step}
        onChange={(event) => {
          onChange(Number(event.target.value))
        }}
        className="h-1 flex-1 accent-[var(--color-accent)]"
      />
      <span className="w-10 text-right tabular-nums text-text-secondary">{value}</span>
    </div>
  )
}

export function Banner({ tone, children }: { tone: "error" | "warn" | "ok"; children: ReactNode }) {
  const tones = {
    error: "border-danger/40 bg-danger/10 text-text-primary",
    warn: "border-warn/40 bg-warn/10 text-text-primary",
    ok: "border-accent/40 bg-accent/10 text-text-primary",
  }
  return (
    <div className={cn("rounded-md border px-3 py-2 text-[13px]", tones[tone])} data-selectable>
      {children}
    </div>
  )
}
