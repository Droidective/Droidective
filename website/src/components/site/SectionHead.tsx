import type { ReactNode } from "react"

import { Reveal } from "@/components/site/Reveal"
import { cn } from "@/lib/utils"

interface SectionHeadProps {
  eyebrow: string
  title: string
  children?: ReactNode
  center?: boolean
}

export function SectionHead({ eyebrow, title, children, center = false }: SectionHeadProps) {
  return (
    <Reveal className={cn("mb-14 max-w-[62ch]", center && "mx-auto text-center")}>
      <span className="font-mono text-[12px] font-medium tracking-[0.06em] text-green/80 uppercase">
        <span className="mr-2 text-green-dim/60">&gt;_</span>
        {eyebrow}
      </span>
      <h2 className="mt-4 mb-4 text-[clamp(28px,4.2vw,46px)] leading-[1.04] font-extrabold tracking-[-0.035em]">
        {title}
      </h2>
      {children && <p className="text-lg leading-relaxed text-muted">{children}</p>}
    </Reveal>
  )
}
