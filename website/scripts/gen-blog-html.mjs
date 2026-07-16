// Generates the static HTML entry for the blog index and each post.
// Titles/subtitles are read from the Markdown so the <head> stays in sync
// with the content. Run: node scripts/gen-blog-html.mjs
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const contentDir = path.join(root, "src/content/blog")
const ORIGIN = "https://droidective.com"

// slug → OG image (absolute path under /blog-media). Video-hero posts fall
// back to a representative screenshot, since OG images can't be video.
const posts = [
  { slug: "command-palette-for-android-debugging", og: "screenshot-palette.png" },
  { slug: "adb-workflow-without-the-terminal", og: "screenshot-logcat.png" },
  { slug: "react-native-debugging-on-mac", og: "screenshot-react.png" },
  { slug: "ios-simulator-companion", og: "screenshot-ios-simulate.png" },
  { slug: "qa-bug-workflow", og: "screenshot-performance.png" },
  { slug: "android-support-diagnostics", og: "screenshot-device.png" },
  { slug: "android-pentest-toolkit", og: "screenshot-apps.png" },
]

const esc = (s) =>
  s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")

function readMeta(slug) {
  const md = readFileSync(path.join(contentDir, `${slug}.md`), "utf8")
  const lines = md.split("\n")
  const title = (lines.find((l) => /^#\s+/.test(l)) ?? "").replace(/^#\s+/, "").trim()
  const subtitle = (lines.find((l) => /^\*[^*].*\*$/.test(l.trim())) ?? "").trim().replace(/^\*|\*$/g, "").trim()
  return { title, subtitle }
}

function page({ title, description, canonical, ogImage, ogType, script }) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />

  <title>${esc(title)}</title>
  <meta name="description" content="${esc(description)}" />
  <meta name="author" content="Rohindh R" />
  <meta name="robots" content="index, follow" />
  <meta name="theme-color" content="#0d0f0e" />
  <link rel="canonical" href="${canonical}" />

  <link rel="icon" type="image/png" href="/assets/icon-64.png" media="(prefers-color-scheme: dark)" />
  <link rel="icon" type="image/png" href="/assets/icon-light-64.png" media="(prefers-color-scheme: light)" />
  <link rel="apple-touch-icon" href="/assets/icon-180.png" />

  <!-- Open Graph -->
  <meta property="og:type" content="${ogType}" />
  <meta property="og:site_name" content="Droidective" />
  <meta property="og:title" content="${esc(title)}" />
  <meta property="og:description" content="${esc(description)}" />
  <meta property="og:url" content="${canonical}" />
  <meta property="og:image" content="${ogImage}" />

  <!-- Twitter -->
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${esc(title)}" />
  <meta name="twitter:description" content="${esc(description)}" />
  <meta name="twitter:image" content="${ogImage}" />

  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:ital,wght@0,400;0,500;0,700;1,400&display=swap" rel="stylesheet" />

  <script src="/analytics.js" defer></script>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/${script}"></script>
</body>
</html>
`
}

// Index page
mkdirSync(path.join(root, "blog"), { recursive: true })
writeFileSync(
  path.join(root, "blog/index.html"),
  page({
    title: "Blog — Droidective",
    description:
      "Guides, deep dives, and role-by-role workflows for debugging Android & React Native on a Mac with Droidective — the free, open-source command palette over adb.",
    canonical: `${ORIGIN}/blog/`,
    ogImage: `${ORIGIN}/assets/screenshot-home.png`,
    ogType: "website",
    script: "blog-main.tsx",
  }),
)

// Post pages
for (const { slug, og } of posts) {
  const { title, subtitle } = readMeta(slug)
  const dir = path.join(root, "blog", slug)
  mkdirSync(dir, { recursive: true })
  writeFileSync(
    path.join(dir, "index.html"),
    page({
      title: `${title} — Droidective`,
      description: subtitle,
      canonical: `${ORIGIN}/blog/${slug}/`,
      ogImage: `${ORIGIN}/blog-media/${og}`,
      ogType: "article",
      script: "blog-post-main.tsx",
    }),
  )
}

console.log(`Generated blog/index.html + ${posts.length} post pages`)
