import { createPortal } from "react-dom"

import { useAppearance } from "@/hooks/useAppearance"
import { grainOpacity } from "@/lib/window-effects"

/**
 * The noise film over the whole window — the Mac's Grain slider.
 *
 * The Mac draws it with a Metal `colorEffect`; there is no Metal here, so the
 * texture is an SVG `feTurbulence` baked into a data URI and tiled. Same
 * intent, same alpha ceiling, and the one property that matters is kept: it
 * sits *outside* the UI zoom transform, so zooming in magnifies the interface
 * and not the specks. That is what the portal is for: `useZoom` sets `zoom` on
 * `#root`, so anything inside it is scaled, and the film has to be a sibling.
 *
 * Fixed rather than absolute, and above everything, because a film that panes
 * could paint over would be a texture on some of the window and not the rest.
 */
export function GrainOverlay() {
  const { grain } = useAppearance()
  const alpha = grainOpacity(grain)
  if (alpha <= 0) return null

  return createPortal(
    <div
      aria-hidden
      className="pointer-events-none fixed inset-0 z-[100]"
      style={{ opacity: alpha, backgroundImage: `url("${NOISE}")`, backgroundRepeat: "repeat" }}
    />,
    globalThis.document.body,
  )
}

/**
 * A 160px tile of monochrome noise.
 *
 * Baked rather than generated at runtime: a canvas of random pixels costs a
 * paint on every resize, and the browser can cache a data URI. The tile is
 * large enough that the repeat is not a visible grid at any window size.
 */
const NOISE = `data:image/svg+xml,${encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160">
     <filter id="n">
       <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="3" stitchTiles="stitch"/>
       <feColorMatrix type="saturate" values="0"/>
     </filter>
     <rect width="160" height="160" filter="url(#n)"/>
   </svg>`,
)}`
