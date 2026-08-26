/**
 * The decompiled-tree rules, kept away from React.
 *
 * A jadx run over a real app writes tens of thousands of files, so the tree is
 * rendered from a flattened list of the rows that are actually visible rather
 * than by recursing components — the same reason the file explorer does. All of
 * it is pure, so it is tested without a decompiler.
 */

import type { DecompileHit, DecompileNode } from "@/lib/wire"

/** One row of the tree as it appears on screen. */
export interface TreeRow {
  node: DecompileNode
  /** Nesting level, for the indent. The root is 0. */
  depth: number
  isDirectory: boolean
  expanded: boolean
}

/**
 * A directory is a node that *has* a children array, empty or not.
 *
 * `children: []` is a real directory that happens to be empty, and reading it
 * as a file would put a source viewer behind a folder.
 */
export function isDirectory(node: DecompileNode): boolean {
  return Array.isArray(node.children)
}

/**
 * The rows to draw, given which directories are open.
 *
 * The root itself is not drawn: it is the output directory, whose name is a
 * cache key (`app-1f2e3d4c-jadx`) rather than anything worth showing.
 */
export function visibleRows(root: DecompileNode, expanded: ReadonlySet<string>): TreeRow[] {
  const rows: TreeRow[] = []
  const walk = (node: DecompileNode, depth: number) => {
    const directory = isDirectory(node)
    const open = directory && expanded.has(node.path)
    rows.push({ node, depth, isDirectory: directory, expanded: open })
    if (!open) return
    for (const child of node.children ?? []) walk(child, depth + 1)
  }
  for (const child of root.children ?? []) walk(child, 0)
  return rows
}

/**
 * The directories to open on arrival.
 *
 * jadx writes `sources/com/example/app/…` and apktool `smali/com/example/…`,
 * so landing on a collapsed tree means four clicks before anything is visible.
 * Following the chain while it has exactly one child directory opens the
 * package path and stops where the tree actually branches — where a choice
 * starts being a choice.
 */
export function defaultExpanded(root: DecompileNode, maxDepth = 12): Set<string> {
  const open = new Set<string>()
  let level = root.children ?? []
  for (let depth = 0; depth < maxDepth; depth += 1) {
    const directories = level.filter((node) => isDirectory(node))
    if (directories.length !== 1 || level.length !== 1) break
    const only = directories[0]
    if (only === undefined) break
    open.add(only.path)
    level = only.children ?? []
  }
  return open
}

/** Toggling one directory open or shut. */
export function toggleExpanded(
  expanded: ReadonlySet<string>,
  path: string,
): Set<string> {
  const next = new Set(expanded)
  if (next.has(path)) next.delete(path)
  else next.add(path)
  return next
}

/**
 * Every directory on the way to `path`, so revealing a search hit opens the
 * tree down to it rather than leaving the row hidden.
 *
 * Derived from the paths themselves rather than by walking the tree: a hit
 * carries only its path, and the tree it belongs to is the one rooted at
 * `root`.
 */
export function ancestors(root: string, path: string): string[] {
  if (!path.startsWith(`${root}/`)) return []
  const rest = path.slice(root.length + 1).split("/")
  const found: string[] = []
  let at = root
  // Every segment but the last, which is the file itself.
  for (const segment of rest.slice(0, -1)) {
    at = `${at}/${segment}`
    found.push(at)
  }
  return found
}

/** A path relative to the output root, which is what a header should show. */
export function relativePath(root: string, path: string): string {
  return path.startsWith(`${root}/`) ? path.slice(root.length + 1) : path
}

/**
 * Search hits grouped by the file they are in, in first-seen order.
 *
 * Ungrouped, 500 hits across a dozen files read as one undifferentiated list;
 * the file is the unit someone navigates by.
 */
export function hitsByFile(hits: readonly DecompileHit[]): { path: string; hits: DecompileHit[] }[] {
  const grouped = new Map<string, DecompileHit[]>()
  for (const hit of hits) {
    const existing = grouped.get(hit.path)
    if (existing === undefined) grouped.set(hit.path, [hit])
    else existing.push(hit)
  }
  return [...grouped].map(([path, found]) => ({ path, hits: found }))
}

/**
 * The CodeMirror-style language hint for a file, by extension.
 *
 * Only what the two decompilers actually emit. Anything else renders as plain
 * text, which is right for a `.dex` dump or an unknown asset.
 */
export function languageOf(path: string): string {
  const dot = path.lastIndexOf(".")
  const extension = dot === -1 ? "" : path.slice(dot + 1).toLowerCase()
  switch (extension) {
    case "java":
      return "java"
    case "kt":
    case "kts":
      return "kotlin"
    case "smali":
      return "smali"
    case "xml":
      return "xml"
    case "json":
      return "json"
    case "properties":
    case "cfg":
    case "pro":
      return "properties"
    case "gradle":
      return "gradle"
    default:
      return "text"
  }
}

/**
 * Whether a file is worth opening in the viewer at all.
 *
 * apktool copies raw assets — PNGs, fonts, `.so` libraries — into its output,
 * and handing one to a text viewer shows a screen of replacement characters.
 * Saying so is more use than rendering it.
 */
const binaryExtensions = new Set([
  "png", "jpg", "jpeg", "gif", "webp", "bmp", "ico", "so", "dex", "ttf", "otf", "zip", "jar",
  "arsc", "bin", "mp3", "mp4", "ogg", "wav", "webm",
])

export function isBinary(path: string): boolean {
  const dot = path.lastIndexOf(".")
  if (dot === -1) return false
  return binaryExtensions.has(path.slice(dot + 1).toLowerCase())
}
