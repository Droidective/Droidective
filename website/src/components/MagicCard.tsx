import { useRef, useState, type MouseEvent, type ReactNode } from "react"

import { useFinePointer } from "@/hooks/useFinePointer"
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion"
import { cn } from "@/lib/utils"

interface MagicCardProps {
  children: ReactNode
  className?: string
  innerClassName?: string
  glowSize?: number
}

export function MagicCard({ children, className, innerClassName, glowSize = 500 }: MagicCardProps) {
  const ref = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState({ x: 0, y: 0 })
  const fine = useFinePointer()
  const reduced = usePrefersReducedMotion()
  const interactive = fine && !reduced

  function handleMove(e: MouseEvent) {
    if (!ref.current || !interactive) return
    const rect = ref.current.getBoundingClientRect()
    setPos({ x: e.clientX - rect.left, y: e.clientY - rect.top })
  }

  return (
    <div
      ref={ref}
      className={cn(
        "group/magic relative overflow-hidden rounded-2xl transition-[transform,border-color,box-shadow] duration-200",
        "border border-white/[0.06] bg-gradient-to-b from-white/[0.035] to-white/0",
        "hover:border-green/25 hover:-translate-y-0.5 hover:shadow-[0_0_40px_-12px_rgba(105,161,6,0.12)]",
        "motion-reduce:hover:translate-y-0",
        className,
      )}
      onMouseMove={handleMove}
      onMouseEnter={() => {}}
      onMouseLeave={() => setPos({ x: -999, y: -999 })}
    >
      {interactive && (
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 z-10 opacity-0 transition-opacity duration-300 group-hover/magic:opacity-100"
          style={{
            background: `radial-gradient(${glowSize}px circle at ${pos.x}px ${pos.y}px, rgba(105,161,6,0.08), transparent 40%)`,
          }}
        />
      )}
      <div className={cn("relative z-0 h-full", innerClassName)}>{children}</div>
    </div>
  )
}
