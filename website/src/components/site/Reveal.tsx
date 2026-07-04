import type { ReactNode } from "react"

import FadeContent from "@/components/FadeContent"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"

interface RevealProps {
  children: ReactNode
  className?: string
  delay?: number
}

/** Scroll-reveal wrapper that renders children statically under reduced motion. */
export function Reveal({ children, className, delay = 0 }: RevealProps) {
  const reducedMotion = usePrefersReducedMotion()
  if (reducedMotion) {
    return <div className={className}>{children}</div>
  }
  return (
    <FadeContent className={className} blur duration={600} delay={delay} threshold={0.08}>
      {children}
    </FadeContent>
  )
}
