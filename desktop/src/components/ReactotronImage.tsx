import { useState } from "react"

/**
 * An `image` event's picture, and the full-size view behind it.
 *
 * Reactotron's client sends a data URI, and this detail used to fall through
 * to the JSON tree — which showed the base64 rather than the image, for an
 * event whose entire point is that you can look at it.
 *
 * Bounded like the Mac's: a preview no larger than 320×240, clicking it for
 * the whole thing. A screenshot from a phone is taller than any detail pane,
 * so showing it at full size inline would push everything else off screen.
 */
export function ReactotronImage({
  uri,
  caption,
  width,
  height,
}: {
  uri: string
  caption?: string | undefined
  width?: number | undefined
  height?: number | undefined
}) {
  const [full, setFull] = useState(false)
  const size = width !== undefined && height !== undefined ? `${String(width)}×${String(height)}` : null

  return (
    <div className="flex flex-col items-start gap-1.5">
      <button
        type="button"
        onClick={() => {
          setFull(true)
        }}
        title="Click to view full size"
        className="max-w-[320px] overflow-hidden rounded-md border border-border-subtle"
      >
        <img src={uri} alt={caption ?? "Logged image"} className="max-h-[240px] w-auto" />
      </button>
      {caption === undefined && size === null ? null : (
        <span className="text-[11.5px] text-text-tertiary">
          {[caption, size].filter(Boolean).join(" · ")}
        </span>
      )}
      {full ? (
        <button
          type="button"
          aria-label="Close the full-size image"
          onClick={() => {
            setFull(false)
          }}
          // The backdrop is the way out, as every other overlay here works:
          // there is nothing to do with a full-size image but look at it and
          // dismiss it.
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-8"
        >
          <img src={uri} alt={caption ?? "Logged image"} className="max-h-full max-w-full" />
        </button>
      ) : null}
    </div>
  )
}
