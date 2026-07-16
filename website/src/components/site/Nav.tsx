import { useEffect, useRef, useState } from "react"

import { ChevronDown, Download, Menu, X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { DOWNLOAD_URL, GITHUB_URL } from "@/lib/content"
import { cn } from "@/lib/utils"

interface NavLink {
  label: string
  href: string
}

const product: NavLink[] = [
  { label: "Features", href: "#features" },
  { label: "Screens", href: "#screenshots" },
  { label: "How it works", href: "#how" },
]

const resources: NavLink[] = [
  { label: "Changelog", href: "/changelog/" },
  { label: "FAQ", href: "#faq" },
  { label: "About", href: "#about" },
]

/** A hover/click nav dropdown. Opens on pointer hover and on click/keyboard,
 *  closes on Escape or outside click; an invisible bridge keeps the pointer
 *  path from the trigger to the panel continuous. */
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
        className="inline-flex items-center gap-1 text-sm font-medium text-muted transition-colors duration-150 hover:text-text data-[open=true]:text-text"
        data-open={open}
      >
        {label}
        <ChevronDown
          className={cn("size-3.5 transition-transform duration-150", open && "rotate-180")}
          aria-hidden
        />
      </button>
      {open && (
        <div className="absolute top-full left-1/2 z-50 -translate-x-1/2 pt-2.5">
          <div className="min-w-46 rounded-xl border border-border-2 bg-popover p-1.5 shadow-[0_16px_40px_-12px_rgba(0,0,0,0.7)]">
            {links.map((link) => (
              <a
                key={link.label}
                href={link.href}
                onClick={() => setOpen(false)}
                className="block rounded-lg px-3 py-2 text-sm font-medium text-muted transition-colors duration-150 hover:bg-white/5 hover:text-text"
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

  return (
    <nav className="sticky top-0 z-100 border-b border-border bg-ink-850/72 backdrop-blur-lg backdrop-saturate-150">
      <div className="mx-auto flex h-[62px] max-w-[1120px] items-center gap-4.5 px-6">
        <a href="#top" className="flex items-center gap-2.75 text-base font-bold tracking-[-0.01em]">
          <img src="/assets/icon-64.png" alt="Droidective icon" width={30} height={30} className="size-7.5 rounded-lg" />
          Droidective
        </a>
        <div className="ml-auto flex items-center gap-6.5">
          <div className="hidden items-center gap-6.5 min-[940px]:flex">
            <NavDropdown label="Product" links={product} />
            <a
              href="#for-you"
              className="text-sm font-medium text-muted transition-colors duration-150 hover:text-text"
            >
              Guides
            </a>
            <a
              href="/blog/"
              className="text-sm font-medium text-muted transition-colors duration-150 hover:text-text"
            >
              Blog
            </a>
            <NavDropdown label="Resources" links={resources} />
            <a
              href={GITHUB_URL}
              className="text-sm font-medium text-muted transition-colors duration-150 hover:text-text"
            >
              GitHub
            </a>
          </div>
          <Button
            asChild
            className="h-auto rounded-xl px-4 py-2 text-sm font-bold shadow-glow hover:bg-green-bright"
          >
            <a href={DOWNLOAD_URL} data-dl="nav">
              <Download aria-hidden />
              Download
            </a>
          </Button>
          <button
            type="button"
            aria-label={menuOpen ? "Close menu" : "Open menu"}
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen((open) => !open)}
            className="-mr-2 grid size-11 cursor-pointer place-items-center rounded-lg text-muted transition-colors duration-150 hover:text-text min-[940px]:hidden"
          >
            {menuOpen ? <X className="size-5.5" aria-hidden /> : <Menu className="size-5.5" aria-hidden />}
          </button>
        </div>
      </div>
      {menuOpen && (
        <div className="border-t border-border px-6 pt-3 pb-5 min-[940px]:hidden">
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
    <div className="border-b border-border py-2 first:pt-0">
      <p className="pb-1 font-mono text-[11.5px] tracking-[0.06em] text-faint uppercase">{label}</p>
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
