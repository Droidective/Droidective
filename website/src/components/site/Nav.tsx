import { useEffect, useRef, useState } from "react"

import { ChevronDown, Download, Menu, Star, X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { DOWNLOAD_URL, GITHUB_URL } from "@/lib/content"
import { cn } from "@/lib/utils"

interface NavLink {
  label: string
  href: string
}

const product: NavLink[] = [
  { label: "Features", href: "#features" },
  { label: "In action", href: "#in-action" },
  { label: "How it works", href: "#how" },
]

const resources: NavLink[] = [
  { label: "Changelog", href: "/changelog/" },
  { label: "FAQ", href: "#faq" },
  { label: "About", href: "#about" },
]

function NavDropdown({ label, links }: { label: string; links: NavLink[] }) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false)
    }
    const onPointer = (e: PointerEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener("keydown", onKey)
    document.addEventListener("pointerdown", onPointer)
    return () => {
      document.removeEventListener("keydown", onKey)
      document.removeEventListener("pointerdown", onPointer)
    }
  }, [open])

  return (
    <div
      ref={ref}
      className="relative"
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
    >
      <button
        type="button"
        aria-expanded={open}
        aria-haspopup="true"
        onClick={() => setOpen((o) => !o)}
        className="inline-flex items-center gap-1 text-[13.5px] font-medium text-muted/80 transition-colors duration-150 hover:text-text data-[open=true]:text-text"
        data-open={open}
      >
        {label}
        <ChevronDown
          className={cn("size-3.5 transition-transform duration-150", open && "rotate-180")}
          aria-hidden
        />
      </button>
      {open && (
        <div className="absolute top-full left-1/2 z-50 -translate-x-1/2 pt-3">
          <div className="min-w-46 rounded-xl border border-white/[0.08] bg-ink-800/95 p-1.5 shadow-[0_16px_40px_-12px_rgba(0,0,0,0.7)] backdrop-blur-xl">
            {links.map((link) => (
              <a
                key={link.label}
                href={link.href}
                onClick={() => setOpen(false)}
                className="block rounded-lg px-3 py-2 text-[13.5px] font-medium text-muted transition-colors duration-150 hover:bg-white/5 hover:text-text"
              >
                {link.label}
              </a>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

export function Nav() {
  const [menuOpen, setMenuOpen] = useState(false)
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40)
    onScroll()
    window.addEventListener("scroll", onScroll, { passive: true })
    return () => window.removeEventListener("scroll", onScroll)
  }, [])

  return (
    <nav
      className={cn(
        "fixed top-0 right-0 left-0 z-100 transition-all duration-300",
        scrolled
          ? "border-b border-white/[0.06] bg-ink-900/80 shadow-[0_4px_30px_-8px_rgba(0,0,0,0.5)] backdrop-blur-2xl backdrop-saturate-150"
          : "border-b border-transparent bg-transparent",
      )}
    >
      <div
        className={cn(
          "mx-auto flex max-w-[1120px] items-center gap-4.5 px-6 transition-[height] duration-300",
          scrolled ? "h-[56px]" : "h-[64px]",
        )}
      >
        <a href="#top" className="flex items-center gap-2.5 text-[15px] font-bold tracking-[-0.01em]">
          <img
            src="/assets/icon-light-64.png"
            alt="Droidective icon"
            width={28}
            height={28}
            className="size-7 rounded-[7px]"
          />
          <span className={cn("transition-opacity duration-300", scrolled ? "opacity-100" : "opacity-80")}>
            Droidective
          </span>
        </a>

        <div className="ml-auto flex items-center gap-6">
          <div className="hidden items-center gap-5.5 min-[940px]:flex">
            <NavDropdown label="Product" links={product} />
            <a
              href="#for-you"
              className="text-[13.5px] font-medium text-muted/80 transition-colors duration-150 hover:text-text"
            >
              Developers
            </a>
            <a
              href="#for-you"
              className="text-[13.5px] font-medium text-muted/80 transition-colors duration-150 hover:text-text"
            >
              Guides
            </a>
            <a
              href="/blog/"
              className="text-[13.5px] font-medium text-muted/80 transition-colors duration-150 hover:text-text"
            >
              Blog
            </a>
            <NavDropdown label="Resources" links={resources} />
          </div>

          <div className="hidden items-center gap-2.5 min-[940px]:flex">
            <a
              href={GITHUB_URL}
              className="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[13px] font-medium text-muted/80 transition-colors duration-150 hover:bg-white/5 hover:text-text"
            >
              <Star className="size-3.5" aria-hidden />
              GitHub
            </a>
            <Button
              asChild
              className={cn(
                "h-auto rounded-xl px-4 py-2 text-[13px] font-bold transition-all duration-200",
                scrolled
                  ? "shadow-glow hover:bg-green-bright"
                  : "bg-green/90 shadow-[0_0_0_1px_rgba(105,161,6,0.3)] hover:bg-green",
              )}
            >
              <a href={DOWNLOAD_URL} data-dl="nav">
                <Download className="size-3.5" aria-hidden />
                Download
              </a>
            </Button>
          </div>

          <button
            type="button"
            aria-label={menuOpen ? "Close menu" : "Open menu"}
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen((open) => !open)}
            className="-mr-2 grid size-10 cursor-pointer place-items-center rounded-lg text-muted transition-colors duration-150 hover:text-text min-[940px]:hidden"
          >
            {menuOpen ? <X className="size-5" aria-hidden /> : <Menu className="size-5" aria-hidden />}
          </button>
        </div>
      </div>

      {menuOpen && (
        <div className="border-t border-white/[0.06] bg-ink-900/95 px-6 pt-3 pb-5 backdrop-blur-2xl min-[940px]:hidden">
          <MobileGroup label="Product" links={product} onNavigate={() => setMenuOpen(false)} />
          <a
            href="#for-you"
            onClick={() => setMenuOpen(false)}
            className="block py-2.5 text-[15px] font-medium text-muted transition-colors duration-150 hover:text-text"
          >
            Guides
          </a>
          <a
            href="/blog/"
            onClick={() => setMenuOpen(false)}
            className="block py-2.5 text-[15px] font-medium text-muted transition-colors duration-150 hover:text-text"
          >
            Blog
          </a>
          <MobileGroup label="Resources" links={resources} onNavigate={() => setMenuOpen(false)} />
          <a
            href={GITHUB_URL}
            onClick={() => setMenuOpen(false)}
            className="block py-2.5 text-[15px] font-medium text-muted transition-colors duration-150 hover:text-text"
          >
            GitHub
          </a>
          <div className="mt-4 flex gap-3">
            <Button asChild className="h-auto flex-1 rounded-xl px-4 py-2.5 text-sm font-bold shadow-glow hover:bg-green-bright">
              <a href={DOWNLOAD_URL} data-dl="nav-mobile">
                <Download className="size-4" aria-hidden />
                Download for macOS
              </a>
            </Button>
          </div>
        </div>
      )}
    </nav>
  )
}

function MobileGroup({
  label,
  links,
  onNavigate,
}: {
  label: string
  links: NavLink[]
  onNavigate: () => void
}) {
  return (
    <div className="border-b border-white/[0.06] py-2 first:pt-0">
      <p className="pb-1 font-mono text-[11px] tracking-[0.06em] text-faint uppercase">{label}</p>
      {links.map((link) => (
        <a
          key={link.label}
          href={link.href}
          onClick={onNavigate}
          className="block py-2 text-[15px] font-medium text-muted transition-colors duration-150 hover:text-text"
        >
          {link.label}
        </a>
      ))}
    </div>
  )
}
