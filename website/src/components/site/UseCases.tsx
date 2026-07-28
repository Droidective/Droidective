import { Activity, Atom, Bug, Search, ShieldCheck } from "lucide-react"
import type { LucideIcon } from "lucide-react"

import { MagicCard } from "@/components/MagicCard"
import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"

interface UseCase {
  icon: LucideIcon
  role: string
  headline: string
  tools: string[]
  href: string
}

const useCases: UseCase[] = [
  {
    icon: Search,
    role: "Android Developers",
    headline: "Tail logcat, watch performance, browse files, and drive apps — every adb command behind ⌘T.",
    tools: ["Live Logcat", "Performance", "File Explorer", "Device Info"],
    href: "/for-android-developers.html",
  },
  {
    icon: Atom,
    role: "React Native Developers",
    headline: "Dev menu, JS reload, Metro forwarding, built-in Reactotron, and a Hermes JS console — one hub.",
    tools: ["Reactotron", "JS Console", "Metro Port", "Dev Menu"],
    href: "/react-native-debugger.html",
  },
  {
    icon: Bug,
    role: "QA & Testers",
    headline: "Reproduce bugs, capture annotated screenshots, and pull full diagnostics — minutes, not hours.",
    tools: ["Screenshot Editor", "Bug Report", "State Simulation", "Crash Catcher"],
    href: "/for-qa-and-testers.html",
  },
  {
    icon: Activity,
    role: "Support Teams",
    headline: "Mirror the screen, grab logs, and close the ticket without learning adb.",
    tools: ["Screen Mirror", "Logcat", "Device Info", "App Management"],
    href: "/for-support-teams.html",
  },
  {
    icon: ShieldCheck,
    role: "Security & Pentest",
    headline: "Inspect, decompile, and re-sign APKs. Set up Frida, browse app data, and route through Burp.",
    tools: ["APK Studio", "Frida Setup", "Sandbox Browser", "Decompiler"],
    href: "/for-security-testers.html",
  },
]

export function UseCases() {
  return (
    <section id="for-you" className="mx-auto max-w-[1120px] px-6 py-28 max-[620px]:py-20">
      <SectionHead center eyebrow="built for you" title="Whoever you are, it's in here.">
        Droidective fits the way you work — not the other way around.
      </SectionHead>

      <div className="grid grid-cols-3 gap-4 max-[940px]:grid-cols-2 max-[620px]:grid-cols-1">
        {useCases.map((uc, i) => (
          <Reveal key={uc.role} delay={Math.min(i % 3, 2) * 60}>
            <a href={uc.href} className="group block h-full">
              <MagicCard className="h-full">
                <div className="flex h-full min-w-0 flex-col p-6 pb-5.5">
                  <div className="mb-4 grid size-10 place-items-center rounded-xl border border-green/12 bg-green/[0.06] text-green">
                    <uc.icon className="size-5" aria-hidden />
                  </div>
                  <p className="mb-2 font-mono text-[11.5px] font-bold tracking-[0.04em] text-green/80 uppercase">
                    {uc.role}
                  </p>
                  <p className="mb-4 flex-1 text-[14.5px] leading-relaxed text-muted/90">{uc.headline}</p>
                  <div className="flex flex-wrap gap-1.5">
                    {uc.tools.map((tool) => (
                      <span
                        key={tool}
                        className="rounded-md border border-white/[0.04] bg-white/[0.02] px-2 py-0.5 font-mono text-[10.5px] text-faint transition-colors duration-200 group-hover:border-green/15 group-hover:text-muted"
                      >
                        {tool}
                      </span>
                    ))}
                  </div>
                  <span className="mt-4 pt-3 border-t border-white/[0.04] font-mono text-[12px] font-medium text-green/70 transition-colors duration-200 group-hover:text-green">
                    Read the guide →
                  </span>
                </div>
              </MagicCard>
            </a>
          </Reveal>
        ))}
      </div>
    </section>
  )
}
