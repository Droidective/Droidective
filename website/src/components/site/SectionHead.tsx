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
    <Reveal className={cn("mb-13 max-w-[62ch]", center && "mx-auto text-center")}>
      <span className="font-mono text-[12.5px] font-medium tracking-[0.04em] text-green">
        <span className="mr-2 text-green-dim">&gt;_</span>
        {eyebrow}
      </span>
      <h2 className="mt-3.5 mb-4 text-[clamp(28px,4.2vw,44px)] leading-[1.04] font-extrabold tracking-[-0.03em]">
        {title}
      </h2>
      {children && <p className="text-lg text-muted">{children}</p>}
    </Reveal>
  )
}
