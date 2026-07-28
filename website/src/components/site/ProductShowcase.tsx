import { useState } from "react"

import { Activity, Atom, Cast, ScrollText, Search } from "lucide-react"
import type { LucideIcon } from "lucide-react"

import { LazyVideo } from "@/components/site/LazyVideo"
import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { cn } from "@/lib/utils"

interface ShowcaseTab {
  id: string
  icon: LucideIcon
  label: string
  image: string
  video?: string
  poster?: string
  caption: string
}

const tabs: ShowcaseTab[] = [
  {
    id: "palette",
    icon: Search,
    label: "Command Palette",
    image: "/assets/screenshot-palette.webp",
    caption: "Hit ⌘T and fuzzy-search all 59 tools. Pin favorites, bind global hotkeys, run on every device.",
  },
  {
    id: "logcat",
    icon: ScrollText,
    label: "Live Logcat",
    image: "/assets/screenshot-logcat.webp",
    caption: "Stream logs with level, tag, and per-app filters. Crash catcher formats stack traces for Slack.",
  },
  {
    id: "performance",
    icon: Activity,
    label: "Performance",
    image: "/assets/screenshot-performance.webp",
    caption: "Per-core CPU, system RAM, app FPS & jank, and network throughput — charted live, exportable.",
  },
  {
    id: "mirror",
    icon: Cast,
    label: "Screen Mirror",
    image: "/assets/poster-tabs.webp",
    video: "/assets/tour-tabs.mp4",
    poster: "/assets/poster-tabs.webp",
    caption: "Mirror and control the device with a GUI for scrcpy — tune bitrate, FPS, crop, and record.",
  },
  {
    id: "react",
    icon: Atom,
    label: "React Native",
    image: "/assets/screenshot-react.webp",
    caption: "Dev menu, JS reload, Metro port forwarding, built-in Reactotron — the whole RN stack in one hub.",
  },
]

export function ProductShowcase() {
  const [active, setActive] = useState(0)
  const tab = tabs[active]!

  return (
    <section id="in-action" className="mx-auto max-w-[1120px] px-6 py-28 max-[620px]:py-20">
      <SectionHead center eyebrow="see it in action" title="Your entire debugging workflow, visualized.">
        Real screens from the actual app driving a live Android device — no mockups.
      </SectionHead>

      {/* Tab bar */}
      <Reveal className="mb-8">
        <div className="mx-auto flex max-w-fit gap-1 rounded-2xl border border-white/[0.06] bg-white/[0.02] p-1.5 max-[620px]:flex-wrap max-[620px]:justify-center">
          {tabs.map((t, i) => (
            <button
              key={t.id}
              type="button"
              onClick={() => setActive(i)}
              className={cn(
                "flex items-center gap-2 rounded-xl px-4 py-2.5 font-mono text-[12.5px] font-medium transition-all duration-200",
                i === active
                  ? "bg-green/12 text-green shadow-[inset_0_0_0_1px_rgba(105,161,6,0.2)]"
                  : "text-muted/70 hover:bg-white/[0.04] hover:text-text",
              )}
            >
              <t.icon className="size-4 max-[620px]:hidden" aria-hidden />
              {t.label}
            </button>
          ))}
        </div>
      </Reveal>

      {/* Showcase panel */}
      <Reveal>
        <div className="relative overflow-hidden rounded-2xl border border-white/[0.06] bg-gradient-to-b from-ink-700/50 to-ink-800/50 shadow-[0_40px_100px_-30px_rgba(0,0,0,0.6)]">
          {/* Ambient glow behind */}
          <div
            aria-hidden
            className="pointer-events-none absolute -top-20 left-1/2 h-40 w-[80%] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(105,161,6,0.06),transparent_70%)] blur-2xl"
          />
          {tab.video ? (
            <LazyVideo
              src={tab.video}
              poster={tab.poster ?? tab.image}
              width={1280}
              height={810}
              label={`Droidective ${tab.label} in action`}
            />
          ) : (
            <img
              src={tab.image}
              alt={`Droidective ${tab.label}`}
              width={1600}
              height={1012}
              loading="lazy"
              decoding="async"
              className="block h-auto w-full"
            />
          )}
        </div>
        <p className="mt-5 text-center text-[15px] text-muted">{tab.caption}</p>
      </Reveal>
    </section>
  )
}
