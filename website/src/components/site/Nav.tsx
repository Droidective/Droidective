import { useEffect, useState } from "react"

import { Download, Menu, X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { DOWNLOAD_URL, GITHUB_URL } from "@/lib/content"
import { cn } from "@/lib/utils"

const links = [
  { label: "Features", href: "#features" },
  { label: "Workflows", href: "#workflows" },
  { label: "Platforms", href: "#platforms" },
  { label: "Why Droidective", href: "#why" },
  { label: "Changelog", href: "/changelog/" },
  { label: "Blog", href: "/blog/" },
]

function GithubMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden className={className}>
      <path d="M12 1.5A10.5 10.5 0 0 0 8.7 22c.5.1.7-.2.7-.5v-1.8c-2.9.6-3.5-1.4-3.5-1.4-.5-1.2-1.2-1.5-1.2-1.5-.9-.6.1-.6.1-.6 1 .1 1.6 1 1.6 1 .9 1.6 2.4 1.1 3 .9.1-.7.4-1.1.6-1.4-2.3-.3-4.7-1.2-4.7-5.1 0-1.1.4-2 1-2.7-.1-.3-.5-1.3.1-2.7 0 0 .8-.3 2.7 1a9.4 9.4 0 0 1 5 0c1.9-1.3 2.7-1 2.7-1 .6 1.4.2 2.4.1 2.7.6.7 1 1.6 1 2.7 0 3.9-2.4 4.8-4.7 5.1.4.3.7 1 .7 2v2.9c0 .3.2.6.7.5A10.5 10.5 0 0 0 12 1.5" />
    </svg>
  )
}

/** A floating, fully-bordered island rather than a full-width bar — the border
 *  wraps all four sides and the pill sits inset from the page edges. */
export function Nav() {
  const [menuOpen, setMenuOpen] = useState(false)
  const [scrolled, setScrolled] = useState(false)

  /* A scroll listener fires on every frame and re-renders this tree each time.
     One IntersectionObserver on a sentinel at the top of the page reports the
     same boolean, and only when it actually changes. */
  useEffect(() => {
    const sentinel = document.createElement("div")
    sentinel.setAttribute("aria-hidden", "true")
    Object.assign(sentinel.style, {
      position: "absolute",
      top: "0",
      left: "0",
      height: "24px",
      width: "1px",
      pointerEvents: "none",
    })
    document.body.prepend(sentinel)

    const observer = new IntersectionObserver(
      ([entry]) => setScrolled(!entry.isIntersecting),
      { threshold: 0 },
    )
    observer.observe(sentinel)
    return () => {
      observer.disconnect()
      sentinel.remove()
    }
  }, [])

  useEffect(() => {
    if (!menuOpen) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [menuOpen])

  return (
    <div
      className={cn(
        "fixed top-0 right-0 left-0 z-100 px-4 transition-[padding] duration-300 max-[620px]:px-3",
        scrolled ? "pt-2.5" : "pt-4 max-[620px]:pt-3",
      )}
    >
      <nav
        className={cn(
          "mx-auto max-w-[1140px] overflow-hidden rounded-2xl border transition-all duration-300",
          scrolled
            ? "border-white/[0.09] bg-ink-900/80 shadow-[0_8px_32px_-8px_rgba(0,0,0,0.6)] backdrop-blur-2xl backdrop-saturate-150"
            : "border-white/[0.06] bg-ink-900/45 backdrop-blur-xl",
        )}
      >
        <div className="flex h-[58px] items-center px-4 max-[620px]:h-[54px] max-[620px]:px-3">
          {/* Brand — larger mark with a ring and a soft green bloom on hover */}
          <a href="#top" className="group/brand flex shrink-0 items-center gap-2.75">
            <span className="relative grid place-items-center">
              <span
                aria-hidden
                className="absolute inset-0 rounded-[10px] bg-green/25 opacity-0 blur-md transition-opacity duration-300 group-hover/brand:opacity-100"
              />
              <img
                src="/assets/icon-light-64.png"
                alt="Droidective icon"
                width={34}
                height={34}
                className="relative size-8.5 rounded-[10px] ring-1 ring-white/12 transition-transform duration-300 group-hover/brand:scale-[1.04] max-[620px]:size-8"
              />
            </span>
            <span className="text-[16px] font-bold tracking-[-0.02em] max-[620px]:text-[15px]">Droidective</span>
          </a>

          {/* Center nav */}
          <div className="mx-auto hidden items-center gap-0.5 min-[1080px]:flex">
            {links.map((l) => (
              <a
                key={l.label}
                href={l.href}
                className="group relative rounded-lg px-3 py-1.5 text-[13.5px] font-medium text-muted/80 transition-colors duration-200 hover:text-text"
              >
                {l.label}
                <span
                  aria-hidden
                  className="absolute bottom-0.5 left-3 h-px w-0 bg-green/60 transition-[width] duration-250 group-hover:w-[calc(100%-24px)] motion-reduce:transition-none"
                />
              </a>
            ))}
          </div>

          {/* Actions */}
          <div className="ml-auto flex items-center gap-2 min-[1080px]:ml-0">
            <a
              href={GITHUB_URL}
              className="hidden items-center gap-1.75 rounded-lg border border-white/[0.07] px-2.75 py-1.5 text-[12.5px] font-medium text-muted/85 transition-all duration-200 hover:border-white/[0.14] hover:bg-white/[0.05] hover:text-text min-[820px]:inline-flex"
            >
              <GithubMark className="size-3.5" />
              Star on GitHub
            </a>
            {/* Compact GitHub affordance below 820px so it never disappears */}
            <a
              href={GITHUB_URL}
              aria-label="Star Droidective on GitHub"
              className="grid size-9 place-items-center rounded-lg border border-white/[0.07] text-muted/85 transition-colors duration-200 hover:border-white/[0.14] hover:text-text min-[820px]:hidden"
            >
              <GithubMark className="size-4" />
            </a>
            <Button
              asChild
              className="h-auto rounded-xl px-4 py-2 text-[13px] font-bold shadow-glow transition-all duration-200 hover:-translate-y-px hover:bg-green-bright"
            >
              <a href={DOWNLOAD_URL} data-dl="nav">
                <Download className="size-3.5" aria-hidden />
                Download
              </a>
            </Button>
            <button
              type="button"
              aria-label={menuOpen ? "Close menu" : "Open menu"}
              aria-expanded={menuOpen}
              onClick={() => setMenuOpen((o) => !o)}
              className="grid size-9 cursor-pointer place-items-center rounded-lg text-muted transition-colors duration-150 hover:text-text min-[1080px]:hidden"
            >
              {menuOpen ? <X className="size-5" aria-hidden /> : <Menu className="size-5" aria-hidden />}
            </button>
          </div>
        </div>

        {/* Drawer lives inside the pill so the border stays continuous */}
        <div
          className={cn(
            "overflow-hidden border-t border-white/[0.06] transition-[max-height,opacity] duration-300 min-[1080px]:hidden",
            menuOpen ? "max-h-[400px] opacity-100" : "max-h-0 opacity-0",
          )}
        >
          <div className="px-4 py-2">
            {links.map((l, i) => (
              <a
                key={l.label}
                href={l.href}
                onClick={() => setMenuOpen(false)}
                style={{ transitionDelay: menuOpen ? `${i * 40}ms` : "0ms" }}
                className={cn(
                  "block border-b border-white/[0.04] py-3.5 text-[15px] font-medium text-muted transition-all duration-300 last:border-0 hover:text-green",
                  menuOpen ? "translate-y-0 opacity-100" : "-translate-y-1 opacity-0",
                )}
              >
                {l.label}
              </a>
            ))}
            <a
              href={GITHUB_URL}
              onClick={() => setMenuOpen(false)}
              className="mt-2 mb-2 flex items-center justify-center gap-2 rounded-xl border border-white/[0.08] bg-white/[0.03] py-2.5 text-[14px] font-semibold text-muted transition-colors hover:text-text"
            >
              <GithubMark className="size-4" />
              Star on GitHub
            </a>
          </div>
        </div>
      </nav>
    </div>
  )
}
