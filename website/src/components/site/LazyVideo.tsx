import { useEffect, useRef } from "react"

import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"

interface LazyVideoProps {
  src: string
  poster?: string
  width?: number
  height?: number
  label: string
  className?: string
}

/** A muted looping showcase video that sits on its poster until scrolled into
 *  view, then plays — and pauses again when scrolled away. With a poster,
 *  `preload="none"` keeps the file off the wire entirely until it is actually
 *  needed (the old `autoPlay` forced every video to download on page load);
 *  without one, `preload="metadata"` lets the browser paint a first frame.
 *  Under reduced motion it stays put with controls instead. */
export function LazyVideo({ src, poster, width, height, label, className }: LazyVideoProps) {
  const reducedMotion = usePrefersReducedMotion()
  const ref = useRef<HTMLVideoElement>(null)

  useEffect(() => {
    if (reducedMotion) return
    const video = ref.current
    if (!video) return
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) {
          void video.play().catch(() => {})
        } else {
          video.pause()
        }
      },
      { rootMargin: "100px" },
    )
    observer.observe(video)
    return () => observer.disconnect()
  }, [reducedMotion])

  return (
    <video
      ref={ref}
      className={className ?? "block h-auto w-full"}
      controls={reducedMotion}
      muted
      loop
      playsInline
      preload={poster ? "none" : "metadata"}
      poster={poster}
      width={width}
      height={height}
      aria-label={label}
    >
      <source src={src} type="video/mp4" />
    </video>
  )
}
