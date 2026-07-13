import type { ReactNode } from "react"

/** A parsed block of a blog post body. */
export type Block =
  | { kind: "heading"; text: string }
  | { kind: "para"; text: string }
  | { kind: "figure"; src: string; alt: string; caption?: string; isVideo: boolean }
  | { kind: "list"; items: string[] }
  | { kind: "callout"; text: string }

export interface ParsedPost {
  title: string
  subtitle: string
  blocks: Block[]
}

const H1 = /^#\s+(.*)$/
const HEADING = /^##\s+(.*)$/
const IMG = /^!\[([^\]]*)\]\(([^)]+)\)\s*$/
const ITALIC_LINE = /^\*([^*].*?)\*$/
const LIST = /^[*-]\s+(.*)$/
const QUOTE = /^>\s?(.*)$/

/**
 * Parse the constrained Markdown the blog posts are authored in into a flat
 * block list. Handles: one H1 title, a leading italic subtitle, H2 section
 * headings, images with an adjacent italic caption, bullet lists, blockquote
 * callouts, and paragraphs. Inline emphasis is rendered later by `Inline`.
 */
export function parsePost(md: string): ParsedPost {
  const lines = md.replace(/\r\n/g, "\n").split("\n")
  let title = ""
  let subtitle = ""
  const blocks: Block[] = []
  let i = 0

  for (; i < lines.length; i++) {
    const m = lines[i].match(H1)
    if (m) {
      title = m[1].trim()
      i++
      break
    }
  }

  for (; i < lines.length; i++) {
    const line = lines[i].trim()
    if (!line) continue
    const m = line.match(ITALIC_LINE)
    if (m) {
      subtitle = m[1].trim()
      i++
    }
    break
  }

  let para: string[] = []
  const flushPara = () => {
    if (para.length) {
      blocks.push({ kind: "para", text: para.join(" ") })
      para = []
    }
  }

  while (i < lines.length) {
    const line = lines[i].trim()
    if (!line || line === "---") {
      flushPara()
      i++
      continue
    }

    const heading = line.match(HEADING)
    if (heading) {
      flushPara()
      blocks.push({ kind: "heading", text: heading[1].trim() })
      i++
      continue
    }

    const img = line.match(IMG)
    if (img) {
      flushPara()
      const alt = img[1].trim()
      const src = img[2].trim()
      let caption: string | undefined
      const next = (lines[i + 1] ?? "").trim()
      const cap = next.match(ITALIC_LINE)
      if (cap) {
        caption = cap[1].trim()
        i++
      }
      blocks.push({ kind: "figure", src, alt, caption, isVideo: src.endsWith(".mp4") })
      i++
      continue
    }

    if (LIST.test(line)) {
      flushPara()
      const items: string[] = []
      while (i < lines.length) {
        const item = lines[i].trim().match(LIST)
        if (!item) break
        items.push(item[1].trim())
        i++
      }
      blocks.push({ kind: "list", items })
      continue
    }

    const quote = line.match(QUOTE)
    if (quote) {
      flushPara()
      const parts: string[] = []
      while (i < lines.length) {
        const q = lines[i].trim().match(QUOTE)
        if (!q) break
        parts.push(q[1].trim())
        i++
      }
      blocks.push({ kind: "callout", text: parts.join(" ") })
      continue
    }

    para.push(line)
    i++
  }
  flushPara()

  return { title, subtitle, blocks }
}

const INLINE = /(`[^`]+`|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)|\*[^*]+\*)/g
const LINK = /^\[([^\]]+)\]\(([^)]+)\)$/

/** Render a constrained set of inline Markdown (code, bold, links, italic). */
export function Inline({ text }: { text: string }): ReactNode {
  const parts = text.split(INLINE).filter((part) => part !== "")
  return parts.map((part, idx) => {
    if (part.length > 1 && part.startsWith("`") && part.endsWith("`")) {
      return (
        <code
          key={idx}
          className="rounded-[5px] border border-border bg-ink-800 px-[6px] py-[2px] font-mono text-[0.86em] text-green-bright"
        >
          {part.slice(1, -1)}
        </code>
      )
    }
    if (part.startsWith("**") && part.endsWith("**")) {
      return (
        <strong key={idx} className="font-semibold text-text">
          {part.slice(2, -2)}
        </strong>
      )
    }
    const link = part.match(LINK)
    if (link) {
      const href = link[2]
      const external = /^https?:\/\//.test(href)
      return (
        <a
          key={idx}
          href={href}
          className="font-medium text-green underline decoration-green/30 underline-offset-2 transition-colors duration-150 hover:decoration-green"
          {...(external ? { target: "_blank", rel: "noopener noreferrer" } : {})}
        >
          {link[1]}
        </a>
      )
    }
    if (part.length > 1 && part.startsWith("*") && part.endsWith("*")) {
      return (
        <em key={idx} className="text-text/90 italic">
          {part.slice(1, -1)}
        </em>
      )
    }
    return <span key={idx}>{part}</span>
  })
}
