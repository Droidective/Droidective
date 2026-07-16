import type { ReactNode } from "react"

import FadeContent from "@/components/FadeContent"
import { useFinePointer } from "@/hooks/useFinePointer"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"

interface RevealProps {
  children: ReactNode
  className?: string
  delay?: number
}

/** Scroll-reveal wrapper that renders children statically under reduced motion.
 *  The blur half of the reveal is desktop-only: animating `filter: blur()` on
 *  section-sized elements janks mobile GPUs, so touch devices fade only. */
export function Reveal({ children, className, delay = 0 }: RevealProps) {
  const reducedMotion = usePrefersReducedMotion()
  const finePointer = useFinePointer()
  if (reducedMotion) {
    return <div className={className}>{children}</div>
  }
  return (
    <FadeContent className={className} blur={finePointer} duration={600} delay={delay} threshold={0.08}>
      {children}
    </FadeContent>
  )
}
