import type { ReactNode } from "react"

import { Reveal } from "@/components/site/Reveal"
import { cn } from "@/lib/utils"

interface SectionHeadProps {
  /** Optional on purpose.
   *
   *  An eyebrow above every heading produces a templated rhythm where each
   *  section announces itself the same way, and most of the labels repeat what
   *  the heading already says ("faq" over "Questions, answered."). It earns its
   *  place only where it categorises something the heading does not, so the
   *  page keeps at most one per three sections. */
  eyebrow?: string
  title: string
  children?: ReactNode
  center?: boolean
}

export function SectionHead({ eyebrow, title, children, center = false }: SectionHeadProps) {
  return (
    <Reveal className={cn("mb-14 max-w-[62ch]", center && "mx-auto text-center")}>
      {eyebrow && (
        <span className="font-mono text-[12px] font-medium tracking-[0.06em] text-green/80 uppercase">
          <span className="mr-2 text-green-dim/60">&gt;_</span>
          {eyebrow}
        </span>
      )}
      <h2
        className={cn(
          "display mb-4 text-[clamp(28px,4.2vw,46px)] leading-[1.04]",
          eyebrow ? "mt-4" : "mt-0",
        )}
      >
        {title}
      </h2>
      {children && <p className="prose-balance text-lg leading-relaxed text-muted">{children}</p>}
    </Reveal>
  )
}
