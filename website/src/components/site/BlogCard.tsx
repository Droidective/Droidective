import { Clock } from "lucide-react"

import { LazyVideo } from "@/components/site/LazyVideo"
import type { BlogPost } from "@/lib/blogPosts"

/** A thumbnail card for the blog index grid. */
export function BlogCard({ post, surface = "index-grid" }: { post: BlogPost; surface?: string }) {
  return (
    <a
      href={`/blog/${post.slug}/`}
      className="group block h-full"
      data-blog-card={post.slug}
      data-blog-surface={surface}
    >
      <article className="flex h-full flex-col overflow-hidden rounded-2xl border border-border bg-linear-to-b from-white/2 to-white/0 transition-[transform,border-color] duration-150 group-hover:-translate-y-[3px] group-hover:border-green/30 motion-reduce:group-hover:translate-y-0">
        {post.hero && (
          <div className="relative aspect-[16/10] overflow-hidden border-b border-border bg-ink-800">
            {post.hero.isVideo ? (
              <LazyVideo
                className="size-full object-cover object-top"
                src={post.hero.src}
                label={post.hero.alt}
              />
            ) : (
              <img
                className="size-full object-cover object-top transition-transform duration-300 group-hover:scale-[1.03] motion-reduce:group-hover:scale-100"
                src={post.hero.src}
                alt={post.hero.alt}
                loading="lazy"
              />
            )}
          </div>
        )}
        <div className="flex flex-1 flex-col p-5.5">
          <div className="mb-3 flex items-center gap-2.5 font-mono text-[11.5px] text-muted">
            <span className="rounded-full border border-green/20 bg-green/8 px-2.5 py-0.75 font-medium text-green">
              {post.role}
            </span>
            <span className="inline-flex items-center gap-1">
              <Clock className="size-3" aria-hidden />
              {post.readMinutes} min
            </span>
          </div>
          <h3 className="mb-2 text-[17.5px] leading-[1.3] font-bold tracking-[-0.015em] transition-colors duration-150 group-hover:text-green-bright">
            {post.title}
          </h3>
          <p className="line-clamp-2 text-[14.5px] leading-[1.55] text-muted">{post.subtitle}</p>
          <span className="mt-4 pt-1 font-mono text-[12.5px] text-faint">{post.dateLabel}</span>
        </div>
      </article>
    </a>
  )
}
