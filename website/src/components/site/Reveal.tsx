import type { ReactNode } from "react"

import FadeContent from "@/components/FadeContent"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"

interface RevealProps {
  children: ReactNode
  className?: string
  delay?: number
}

/** Scroll-reveal wrapper. Renders children statically under reduced motion.
 *
 *  The reveal moves and fades; it does not blur. Animating `filter: blur()`
 *  repaints the whole subtree every frame for the length of the tween, and on a
 *  page this long a fast scroll brings three or four sections into view at once,
 *  so those repaints stack inside one frame budget. A `translateY` is composited
 *  and costs the same whether it moves one element or a section of them.
 *
 *  This also drops the desktop/touch split the blur needed: one reveal now
 *  behaves the same everywhere, so there is no second path to keep working. */
export function Reveal({ children, className, delay = 0 }: RevealProps) {
  const reducedMotion = usePrefersReducedMotion()
  if (reducedMotion) {
    return <div className={className}>{children}</div>
  }
  return (
    <FadeContent className={className} y={18} duration={600} delay={delay} threshold={0.08}>
      {children}
    </FadeContent>
  )
}
