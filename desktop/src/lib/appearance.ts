/**
 * Theme and accent — the Appearance tab's model.
 *
 * The light and dark values are lifted from the Mac's asset catalog
 * (`BgRoot`, `BgSurface`, `BorderSubtle`, `TextMain`, `TextMuted`,
 * `BrandAccent`) rather than picked to look similar, so the two products are
 * the same colour instead of approximately the same colour. Everything here is
 * pure: applying it is one `style.setProperty` loop in the provider.
 */

export type Theme = "light" | "dark" | "system"

/** The Mac's three choices, in its order. */
export const THEMES: readonly { value: Theme; label: string }[] = [
  { value: "light", label: "Light" },
  { value: "dark", label: "Dark" },
  { value: "system", label: "System" },
]

/** The Mac's default accent, and the presets its picker offers. */
export const DEFAULT_ACCENT = "#6ecc1f"

export const ACCENT_PRESETS: readonly { value: string; label: string }[] = [
  { value: "#6ecc1f", label: "Droid Green" },
  { value: "#0a84ff", label: "Blue" },
  { value: "#bf5af2", label: "Purple" },
  { value: "#ff9f0a", label: "Orange" },
  { value: "#ff375f", label: "Pink" },
  { value: "#64d2ff", label: "Cyan" },
]

/** One theme's tokens, keyed by the CSS custom property they set. */
export type Palette = Readonly<Record<string, string>>

const DARK: Palette = {
  "--color-bg-root": "#1a1a1a",
  "--color-bg-surface": "#232323",
  "--color-bg-chrome": "#1e1e1e",
  "--color-bg-raised": "#2c2c2c",
  "--color-border-subtle": "#333333",
  "--color-text-primary": "#ececec",
  "--color-text-secondary": "#929292",
  "--color-text-tertiary": "#6f6f6f",
}

const LIGHT: Palette = {
  "--color-bg-root": "#f5f6f7",
  "--color-bg-surface": "#ffffff",
  // Between root and surface, as the dark set is: the sidebar and toolbars sit
  // a step off the content on both platforms.
  "--color-bg-chrome": "#eceef0",
  "--color-bg-raised": "#e6e8eb",
  "--color-border-subtle": "#e3e5e8",
  "--color-text-primary": "#181a1c",
  "--color-text-secondary": "#6a6e73",
  "--color-text-tertiary": "#8b9096",
}

/** Which palette a setting resolves to right now. */
export function resolveTheme(theme: Theme, prefersDark: boolean): "light" | "dark" {
  if (theme === "system") return prefersDark ? "dark" : "light"
  return theme
}

export function palette(theme: "light" | "dark"): Palette {
  return theme === "dark" ? DARK : LIGHT
}

/**
 * The accent as the app should apply it.
 *
 * The Mac's accent is one colour in both themes except for the default, which
 * darkens in light mode so green-on-white stays legible — that is the
 * `BrandAccent` colorset's own light value, not a rule invented here.
 */
export function accentFor(accent: string, theme: "light" | "dark"): string {
  if (theme === "light" && accent.toLowerCase() === DEFAULT_ACCENT) return "#468a10"
  return accent
}

/** WCAG contrast between two colours, 1…21. */
export function contrastRatio(one: string, other: string): number {
  const lighter = Math.max(relativeLuminance(one), relativeLuminance(other))
  const darker = Math.min(relativeLuminance(one), relativeLuminance(other))
  return (lighter + 0.05) / (darker + 0.05)
}

/**
 * A hex string the app can use, or null.
 *
 * Accepts `#rgb` and `#rrggbb`, with or without the hash, because people paste
 * all of those. Anything else is rejected rather than coerced — a half-parsed
 * colour silently applied is worse than a field that says no.
 */
export function normalizeHex(input: string): string | null {
  const raw = input.trim().replace(/^#/u, "").toLowerCase()
  if (/^[\da-f]{3}$/u.test(raw)) {
    return `#${[...raw].map((digit) => digit + digit).join("")}`
  }
  if (/^[\da-f]{6}$/u.test(raw)) return `#${raw}`
  return null
}

/** WCAG relative luminance, for the foreground decision above. */
export function relativeLuminance(hex: string): number {
  const normalized = normalizeHex(hex) ?? DEFAULT_ACCENT
  const channels = [1, 3, 5].map((offset) => {
    const value = Number.parseInt(normalized.slice(offset, offset + 2), 16) / 255
    return value <= 0.039_28 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * (channels[0] ?? 0) + 0.7152 * (channels[1] ?? 0) + 0.0722 * (channels[2] ?? 0)
}

/**
 * Whether an accent is too close to the surface it sits on.
 *
 * The Mac shows a low-contrast warning rather than refusing the colour — it is
 * the user's app — and this is the same contrast ratio behind it.
 */
export function isLowContrast(accent: string, theme: "light" | "dark"): boolean {
  return contrastRatio(accent, theme === "dark" ? "#1a1a1a" : "#f5f6f7") < 3
}
