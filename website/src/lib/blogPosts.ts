import { type Block, parsePost } from "@/lib/markdown"

/** Editorial metadata for a post. Body content lives in the Markdown file. */
interface PostMeta {
  slug: string
  role: string
  dateISO: string
  dateLabel: string
  readMinutes: number
  tags: string[]
  featured?: boolean
}

/** Ordered — the first entry (featured) leads the index; the rest follow. */
const META: PostMeta[] = [
  {
    slug: "command-palette-for-android-debugging",
    role: "Overview",
    dateISO: "2026-07-13",
    dateLabel: "Jul 13, 2026",
    readMinutes: 6,
    tags: ["Android", "React Native", "adb"],
    featured: true,
  },
  {
    slug: "adb-workflow-without-the-terminal",
    role: "Android",
    dateISO: "2026-07-12",
    dateLabel: "Jul 12, 2026",
    readMinutes: 5,
    tags: ["Android", "logcat", "adb"],
  },
  {
    slug: "react-native-debugging-on-mac",
    role: "React Native",
    dateISO: "2026-07-12",
    dateLabel: "Jul 12, 2026",
    readMinutes: 4,
    tags: ["React Native", "Reactotron", "Hermes"],
  },
  {
    slug: "ios-simulator-companion",
    role: "iOS",
    dateISO: "2026-07-11",
    dateLabel: "Jul 11, 2026",
    readMinutes: 4,
    tags: ["iOS", "Simulator", "Xcode"],
  },
  {
    slug: "qa-bug-workflow",
    role: "QA",
    dateISO: "2026-07-11",
    dateLabel: "Jul 11, 2026",
    readMinutes: 4,
    tags: ["QA", "Testing", "Bug reports"],
  },
  {
    slug: "android-support-diagnostics",
    role: "Support",
    dateISO: "2026-07-10",
    dateLabel: "Jul 10, 2026",
    readMinutes: 4,
    tags: ["Support", "Diagnostics", "Triage"],
  },
  {
    slug: "android-pentest-toolkit",
    role: "Security",
    dateISO: "2026-07-10",
    dateLabel: "Jul 10, 2026",
    readMinutes: 4,
    tags: ["Security", "Frida", "APK"],
  },
]

const RAW = import.meta.glob("../content/blog/*.md", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>

function rawFor(slug: string): string {
  const entry = Object.entries(RAW).find(([path]) => path.endsWith(`/${slug}.md`))
  if (!entry) throw new Error(`Missing Markdown for blog slug "${slug}"`)
  return entry[1]
}

export interface BlogPost extends PostMeta {
  title: string
  subtitle: string
  blocks: Block[]
  /** First image in the body — used as the card thumbnail and OG image. */
  hero?: { src: string; alt: string; isVideo: boolean }
}

export const posts: BlogPost[] = META.map((meta) => {
  const { title, subtitle, blocks } = parsePost(rawFor(meta.slug))
  const figure = blocks.find((block) => block.kind === "figure")
  const hero =
    figure && figure.kind === "figure"
      ? { src: figure.src, alt: figure.alt, isVideo: figure.isVideo }
      : undefined
  return { ...meta, title, subtitle, blocks, hero }
})

export function getPost(slug: string): BlogPost | undefined {
  return posts.find((post) => post.slug === slug)
}
