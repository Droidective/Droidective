import { createContext, useContext, useEffect, useMemo, useState } from "react"
import {
  accentFor,
  DEFAULT_ACCENT,
  palette,
  resolveTheme,
  type Theme,
} from "@/lib/appearance"

export interface Appearance {
  theme: Theme
  accent: string
  /** What `theme` resolves to right now — never "system". */
  resolved: "light" | "dark"
  setTheme: (theme: Theme) => void
  setAccent: (accent: string) => void
}

const AppearanceContext = createContext<Appearance | null>(null)

const STORAGE_KEY = "droidective.appearance"

interface Saved {
  theme: Theme
  accent: string
}

function load(): Saved {
  const fallback: Saved = { theme: "dark", accent: DEFAULT_ACCENT }
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

  const resolved = resolveTheme(saved.theme, prefersDark)

  useEffect(() => {
    const root = globalThis.document.documentElement
    for (const [token, value] of Object.entries(palette(resolved))) {
      root.style.setProperty(token, value)
    }
    root.style.setProperty("--color-accent", accentFor(saved.accent, resolved))
    // So the webview paints native scrollbars and form controls to match.
    root.style.colorScheme = resolved
  }, [resolved, saved.accent])

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
      resolved,
      setTheme: (theme) => {
        setSaved((current) => ({ ...current, theme }))
      },
      setAccent: (accent) => {
        setSaved((current) => ({ ...current, accent }))
      },
    }),
    [resolved, saved.accent, saved.theme],
  )

  return <AppearanceContext value={value}>{children}</AppearanceContext>
}

export function useAppearance(): Appearance {
  const value = useContext(AppearanceContext)
  if (value === null) throw new Error("useAppearance used outside AppearanceProvider")
  return value
}
