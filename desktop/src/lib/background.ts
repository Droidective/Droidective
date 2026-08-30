import { normalizeHex, palette, type Palette } from "@/lib/appearance"

/**
 * The user-chosen window background and text colour.
 *
 * Ported from ADBKit's `BackgroundPalette` and `TextPalette`: one picked
 * colour, with the lifted surface, the chrome step, the hairline and the muted
 * text *derived* from it by the same contrast steps the stock tokens have
 * between them — so a custom palette keeps the visual hierarchy instead of
 * flattening into one colour.
 *
 * Its own module rather than more of `appearance.ts`: that file is the theme
 * and the accent, and this is arithmetic over a colour the user picked.
 */

/**
 * The Mac's eight presets, in its order.
 *
 * Six dark and two light, and the last two are the point: picking one is also
 * how the light treatment gets chosen, because the scheme follows the colour
 * rather than the Theme picker.
 */
export const BACKGROUND_PRESETS: readonly { value: string; label: string }[] = [
  { value: "#0f172a", label: "Slate" },
  { value: "#0d1b2a", label: "Midnight" },
  { value: "#211a16", label: "Espresso" },
  { value: "#0c1f17", label: "Forest" },
  { value: "#1b1023", label: "Plum" },
  { value: "#1c2126", label: "Steel" },
  { value: "#f7f3ec", label: "Paper" },
  { value: "#eef1f5", label: "Mist" },
]

/** `TextPalette.mutedOpacity`. */
export const MUTED_OPACITY = 0.62

/** Below this Settings warns — and still applies the colour. WCAG AA for UI. */
export const MIN_COMFORTABLE_CONTRAST = 3

/** sRGB components in 0…1 — `BackgroundPalette.RGB`. */
interface RGB {
  red: number
  green: number
  blue: number
}

/**
 * A custom background, expanded into the tokens every pane is painted from.
 *
 * The light/dark treatment follows the colour, which is why the Theme picker is
 * disabled while one is set: a light background under dark-mode text is
 * unreadable, and leaving the two to be kept in step by hand would be asking
 * someone to do this arithmetic themselves.
 */
export function backgroundPalette(hex: string): Palette | null {
  const rgb = parseRGB(hex)
  if (rgb === null) return null
  const light = isLightBackground(rgb)
  return {
    ...palette(light ? "light" : "dark"),
    "--color-bg-root": toHex(rgb),
    // +9/255, the stock dark step (#1A1A1A → #232323).
    "--color-bg-surface": toHex(shifted(rgb, 9 / 255)),
    // Half of it: the sidebar and toolbars sit *between* root and surface.
    "--color-bg-chrome": toHex(shifted(rgb, 4.5 / 255)),
    "--color-bg-raised": toHex(shifted(rgb, 18 / 255)),
    // Dark roots go lighter, light roots darker — `BackgroundPalette.border`.
    "--color-border-subtle": toHex(shifted(rgb, light ? -18 / 255 : 25 / 255)),
  }
}

/**
 * A custom text colour, and the muted tones derived from it.
 *
 * Composited to a solid rather than applied as an opacity, because these are
 * colour *tokens*: a translucent one would show whatever card happened to be
 * behind the text instead of the background it was derived against.
 */
export function textPalette(hex: string, background: string): Palette | null {
  const rgb = parseRGB(hex)
  const behind = parseRGB(background)
  if (rgb === null || behind === null) return null
  return {
    "--color-text-primary": toHex(rgb),
    "--color-text-secondary": toHex(mix(rgb, behind, MUTED_OPACITY)),
    // The stock tertiary sits a further step down; the same ratio again.
    "--color-text-tertiary": toHex(mix(rgb, behind, MUTED_OPACITY * 0.72)),
  }
}

/**
 * The app's own contrast ratio — `TextPalette.contrastRatio`.
 *
 * Deliberately not the `contrastRatio` in `appearance.ts`, which the accent's
 * warning uses: that one linearises sRGB the way WCAG does, and this one uses
 * the gamma-encoded approximation the rest of this file is built on, so its
 * number agrees with `isLightHex`. Porting one onto the other would change
 * which colours the Mac warns about.
 */
export function textContrastRatio(text: string, background: string): number | null {
  const one = parseRGB(text)
  const other = parseRGB(background)
  if (one === null || other === null) return null
  const a = luminance(one)
  const b = luminance(other)
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
}

/** The Mac's 0.35 threshold: above it, dark text and the light treatment. */
export function isLightHex(hex: string): boolean {
  const rgb = parseRGB(hex)
  return rgb !== null && isLightBackground(rgb)
}

function parseRGB(hex: string): RGB | null {
  const normalized = normalizeHex(hex)
  if (normalized === null) return null
  const value = Number.parseInt(normalized.slice(1), 16)
  return {
    red: ((value >> 16) & 0xff) / 255,
    green: ((value >> 8) & 0xff) / 255,
    blue: (value & 0xff) / 255,
  }
}

/** One channel, clamped — a derived step can leave 0…1 at either end. */
function channelHex(value: number): string {
  return Math.round(Math.min(1, Math.max(0, value)) * 255)
    .toString(16)
    .padStart(2, "0")
}

function toHex(rgb: RGB): string {
  return `#${channelHex(rgb.red)}${channelHex(rgb.green)}${channelHex(rgb.blue)}`
}

/** Rec. 709 weights on gamma-encoded sRGB — `BackgroundPalette.luminance`. */
function luminance(rgb: RGB): number {
  return 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
}

function isLightBackground(rgb: RGB): boolean {
  return luminance(rgb) > 0.35
}

function shifted(rgb: RGB, delta: number): RGB {
  return { red: rgb.red + delta, green: rgb.green + delta, blue: rgb.blue + delta }
}

function mix(front: RGB, back: RGB, alpha: number): RGB {
  return {
    red: front.red * alpha + back.red * (1 - alpha),
    green: front.green * alpha + back.green * (1 - alpha),
    blue: front.blue * alpha + back.blue * (1 - alpha),
  }
}
