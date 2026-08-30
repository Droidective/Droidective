import { createContext, useContext, useEffect, useMemo, useState } from "react"
import {
  accentFor,
  DEFAULT_ACCENT,
  normalizeHex,
  palette,
  resolveTheme,
  type Theme,
} from "@/lib/appearance"
import { backgroundPalette, isLightHex, textPalette } from "@/lib/background"

/** A stored colour, or "" for "none chosen" — which a malformed one becomes. */
function hexOrNone(value: unknown): string {
  return typeof value === "string" ? (normalizeHex(value) ?? "") : ""
}

export interface Appearance {
  theme: Theme
  accent: string
  /** A chosen window background, or "" for the stock palette. */
  background: string
  /** A chosen primary text colour, or "" for the palette's own. */
  text: string
  /**
   * What the app is actually painted as right now — never "system", and never
   * the Theme picker's answer while a custom background is set, since the
   * scheme follows that colour.
   */
  resolved: "light" | "dark"
  setTheme: (theme: Theme) => void
  setAccent: (accent: string) => void
  setBackground: (hex: string) => void
  setText: (hex: string) => void
}

const AppearanceContext = createContext<Appearance | null>(null)

const STORAGE_KEY = "droidective.appearance"

interface Saved {
  theme: Theme
  accent: string
  background: string
  text: string
}

function load(): Saved {
  const fallback: Saved = { theme: "dark", accent: DEFAULT_ACCENT, background: "", text: "" }
  try {
    const raw = globalThis.localStorage.getItem(STORAGE_KEY)
    if (raw === null) return fallback
    const parsed = JSON.parse(raw) as Partial<Saved>
    return {
      theme:
        parsed.theme === "light" || parsed.theme === "dark" || parsed.theme === "system"
          ? parsed.theme
          : fallback.theme,
      accent: typeof parsed.accent === "string" ? parsed.accent : fallback.accent,
      // A malformed colour reads as "none chosen" rather than taking the
      // window down with it — `normalizeHex` is what decides, in one place.
      background: hexOrNone(parsed.background),
      text: hexOrNone(parsed.text),
    }
  } catch {
    // Persisted JSON a previous version wrote. A shape that has since changed
    // must not take the window down with it.
    return fallback
  }
}

/**
 * Theme and accent for the whole window.
 *
 * Applied by writing the palette onto `:root` as CSS custom properties, which
 * is what every Tailwind token in this app already reads — so switching theme
 * is one loop rather than a second stylesheet. The Mac does the equivalent with
 * its asset catalog's light/dark pairs.
 */
export function AppearanceProvider({ children }: { children: React.ReactNode }) {
  const [saved, setSaved] = useState<Saved>(load)
  const [prefersDark, setPrefersDark] = useState(
    () => globalThis.matchMedia("(prefers-color-scheme: dark)").matches,
  )

  // Only meaningful on "system", but the listener is cheap and unconditional
  // is one fewer effect to get wrong when the setting changes.
  useEffect(() => {
    const query = globalThis.matchMedia("(prefers-color-scheme: dark)")
    const onChange = (event: MediaQueryListEvent) => {
      setPrefersDark(event.matches)
    }
    query.addEventListener("change", onChange)
    return () => {
      query.removeEventListener("change", onChange)
    }
  }, [])

  // A custom background overrides the Theme picker rather than sitting beside
  // it, exactly as on the Mac: the scheme follows the colour, because a light
  // background under dark-mode text is unreadable and nobody should have to
  // keep two settings in step by hand.
  const custom = saved.background === "" ? null : backgroundPalette(saved.background)
  const resolved =
    custom === null ? resolveTheme(saved.theme, prefersDark) : isLightHex(saved.background)
      ? "light"
      : "dark"

  useEffect(() => {
    const root = globalThis.document.documentElement
    const base = custom ?? palette(resolved)
    const text =
      saved.text === ""
        ? null
        : textPalette(saved.text, base["--color-bg-root"] ?? "#1a1a1a")
    for (const [token, value] of Object.entries({ ...base, ...text })) {
      root.style.setProperty(token, value)
    }
    root.style.setProperty("--color-accent", accentFor(saved.accent, resolved))
    // So the webview paints native scrollbars and form controls to match.
    root.style.colorScheme = resolved
    // `custom` is derived from `saved.background`, which is the dependency
    // that actually changes; depending on the object would re-apply the whole
    // palette on every render.
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [resolved, saved.accent, saved.background, saved.text])

  useEffect(() => {
    try {
      globalThis.localStorage.setItem(STORAGE_KEY, JSON.stringify(saved))
    } catch {
      // Private mode or over quota. Losing a colour is not worth an error.
    }
  }, [saved])

  const value = useMemo<Appearance>(
    () => ({
      theme: saved.theme,
      accent: saved.accent,
      background: saved.background,
      text: saved.text,
      resolved,
      setTheme: (theme) => {
        setSaved((current) => ({ ...current, theme }))
      },
      setAccent: (accent) => {
        setSaved((current) => ({ ...current, accent }))
      },
      setBackground: (background) => {
        setSaved((current) => ({ ...current, background }))
      },
      setText: (text) => {
        setSaved((current) => ({ ...current, text }))
      },
    }),
    [resolved, saved.accent, saved.theme, saved.background, saved.text],
  )

  return <AppearanceContext value={value}>{children}</AppearanceContext>
}

export function useAppearance(): Appearance {
  const value = useContext(AppearanceContext)
  if (value === null) throw new Error("useAppearance used outside AppearanceProvider")
  return value
}
