import { useState } from "react"

import { Download, Menu, X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { DOWNLOAD_URL, GITHUB_URL } from "@/lib/content"

const navLinks = [
  { label: "Features", href: "#features" },
  { label: "Screens", href: "#screenshots" },
  { label: "How it works", href: "#how" },
  { label: "Guides", href: "#for-you" },
  { label: "Blog", href: "/blog/" },
  { label: "Changelog", href: "#changelog" },
  { label: "FAQ", href: "#faq" },
  { label: "About", href: "#about" },
  { label: "GitHub", href: GITHUB_URL },
]

export function Nav() {
  const [menuOpen, setMenuOpen] = useState(false)

  return (
    <nav className="sticky top-0 z-100 border-b border-border bg-ink-850/72 backdrop-blur-lg backdrop-saturate-150">
      <div className="mx-auto flex h-[62px] max-w-[1120px] items-center gap-4.5 px-6">
        <a href="#top" className="flex items-center gap-2.75 text-base font-bold tracking-[-0.01em]">
          <img src="/assets/icon.png" alt="Droidective icon" className="size-7.5 rounded-lg" />
          Droidective
        </a>
        <div className="ml-auto flex items-center gap-6.5">
          {navLinks.map((link) => (
            <a
              key={link.label}
              href={link.href}
              className="hidden text-sm font-medium text-muted transition-colors duration-150 hover:text-text min-[940px]:block"
            >
              {link.label}
            </a>
          ))}
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
        <div className="border-t border-border px-6 pt-2 pb-4 min-[940px]:hidden">
          {navLinks.map((link) => (
            <a
              key={link.label}
              href={link.href}
              onClick={() => setMenuOpen(false)}
              className="block py-2.5 text-[15px] font-medium text-muted transition-colors duration-150 hover:text-text"
            >
              {link.label}
            </a>
          ))}
        </div>
      )}
    </nav>
  )
}
