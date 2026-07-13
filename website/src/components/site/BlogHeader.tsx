import { Download } from "lucide-react"

import { Button } from "@/components/ui/button"
import { DOWNLOAD_URL, GITHUB_URL } from "@/lib/content"

/** Slim sticky header for the blog index and post pages. */
export function BlogHeader() {
  return (
    <nav className="sticky top-0 z-100 border-b border-border bg-ink-850/72 backdrop-blur-lg backdrop-saturate-150">
      <div className="mx-auto flex h-[62px] max-w-[1120px] items-center gap-4.5 px-6">
        <a href="/" className="flex items-center gap-2.75 text-base font-bold tracking-[-0.01em]">
          <img src="/assets/icon.png" alt="Droidective icon" className="size-7.5 rounded-lg" />
          Droidective
        </a>
        <div className="ml-auto flex items-center gap-6.5">
          <a
            href="/"
            className="hidden text-sm font-medium text-muted transition-colors duration-150 hover:text-text min-[620px]:block"
          >
            Home
          </a>
          <a
            href="/blog/"
            className="hidden text-sm font-medium text-text transition-colors duration-150 hover:text-text min-[620px]:block"
          >
            Blog
          </a>
          <a
            href={GITHUB_URL}
            className="hidden text-sm font-medium text-muted transition-colors duration-150 hover:text-text min-[620px]:block"
          >
            GitHub
          </a>
          <Button
            asChild
            className="h-auto rounded-xl px-4 py-2 text-sm font-bold shadow-glow hover:bg-green-bright"
          >
            <a href={DOWNLOAD_URL} data-dl="blog-nav">
              <Download aria-hidden />
              Download
            </a>
          </Button>
        </div>
      </div>
    </nav>
  )
}
