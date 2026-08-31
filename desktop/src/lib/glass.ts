import type { Palette } from "@/lib/appearance"
import { cardAlpha, clampedOpacity, isTranslucent, withAlpha } from "@/lib/window-effects"

/**
 * A palette turned to glass.
 *
 * The Mac's rule, kept exactly: the *root* carries the window opacity, and
 * every lifted surface — the sidebar, chrome, cards — carries only the contrast
 * step, because it stacks on the root wash rather than replacing it. Painting
 * them all at the root's alpha compounds to near-solid and loses the glass
 * everywhere a card sits, which is most of the window.
 *
 * Its own module so the rule is one small tested function rather than a branch
 * inside the appearance provider's effect.
 */

/** The one token painted directly on the window. */
const ROOT_TOKEN = "--color-bg-root"

/**
 * The tokens that sit above the root and therefore only step off it.
 *
 * Borders are not here: a hairline is already a thin light line over whatever
 * is behind it, and fading it out is what makes a translucent window read as
 * one undifferentiated sheet.
 */
const LIFTED_TOKENS = ["--color-bg-surface", "--color-bg-chrome", "--color-bg-raised"]

/**
 * Re-express a palette's backgrounds at the window opacity.
 *
 * At 100% the palette comes back untouched — byte for byte, so a window nobody
 * has touched the slider on renders exactly as it did before the feature
 * existed.
 */
export function glassPalette(base: Palette, opacity: number): Palette {
  if (!isTranslucent(opacity)) return base

  const root = clampedOpacity(opacity)
  const lifted = cardAlpha(root)
  const next: Record<string, string> = { ...base }

  const rootColor = base[ROOT_TOKEN]
  if (rootColor !== undefined) next[ROOT_TOKEN] = withAlpha(rootColor, root)
  for (const token of LIFTED_TOKENS) {
    const color = base[token]
    if (color !== undefined) next[token] = withAlpha(color, lifted)
  }
  return next
}
