import { useEffect } from "react"

import { ArrowRight, Clock } from "lucide-react"

import { BlogCard } from "@/components/site/BlogCard"
import { BlogHeader } from "@/components/site/BlogHeader"
import { Footer } from "@/components/site/Footer"
import { LazyVideo } from "@/components/site/LazyVideo"
import { Reveal } from "@/components/site/Reveal"
import { track } from "@/lib/analytics"
import { posts } from "@/lib/blogPosts"

export function BlogIndexPage() {
  const featured = posts.find((post) => post.featured) ?? posts[0]
  const rest = posts.filter((post) => post.slug !== featured.slug)

  useEffect(() => {
    track("blog_index_viewed", { post_count: posts.length })
  }, [])

  return (
    <>
      <BlogHeader />
      <main>
        {/* Hero */}
        <section className="mx-auto max-w-[1120px] px-6 pt-16 pb-10 max-[620px]:pt-11">
          <Reveal className="max-w-[64ch]">
            <span className="font-mono text-[12.5px] font-medium tracking-[0.04em] text-green">
              <span className="mr-2 text-green-dim">&gt;_</span>
              blog
            </span>
            <h1 className="mt-3.5 mb-4 text-[clamp(32px,5vw,52px)] leading-[1.03] font-extrabold tracking-[-0.035em]">
              The Droidective blog
            </h1>
            <p className="text-[clamp(17px,2vw,20px)] text-muted">
              Guides, deep dives, and role-by-role workflows for debugging Android &amp; React Native on a Mac — no
              terminal required.
            </p>
          </Reveal>
        </section>

        {/* Featured */}
        <section className="mx-auto max-w-[1120px] px-6 pb-4">
          <Reveal>
            <a
              href={`/blog/${featured.slug}/`}
              className="group block"
              data-blog-card={featured.slug}
              data-blog-surface="index-featured"
            >
              <article className="grid overflow-hidden rounded-2xl border border-border bg-linear-to-b from-white/3 to-white/0 transition-[border-color] duration-150 group-hover:border-green/30 min-[820px]:grid-cols-2">
                <div className="relative aspect-[16/10] overflow-hidden border-b border-border bg-ink-800 min-[820px]:aspect-auto min-[820px]:border-r min-[820px]:border-b-0">
                  {featured.hero &&
                    (featured.hero.isVideo ? (
                      <LazyVideo
                        className="size-full object-cover object-top"
                        src={featured.hero.src}
                        label={featured.hero.alt}
                      />
                    ) : (
                      <img
                        className="size-full object-cover object-top"
                        src={featured.hero.src}
                        alt={featured.hero.alt}
                        loading="lazy"
                      />
                    ))}
                </div>
                <div className="flex flex-col justify-center p-8 max-[620px]:p-6">
                  <div className="mb-4 flex items-center gap-2.5 font-mono text-[12px] text-muted">
                    <span className="rounded-full border border-amber/25 bg-amber/10 px-2.5 py-0.75 font-medium text-amber">
                      Featured
                    </span>
                    <span className="rounded-full border border-green/20 bg-green/8 px-2.5 py-0.75 font-medium text-green">
                      {featured.role}
                    </span>
                    <span className="inline-flex items-center gap-1">
                      <Clock className="size-3.25" aria-hidden />
                      {featured.readMinutes} min read
                    </span>
                  </div>
                  <h2 className="mb-3 text-[clamp(23px,3vw,32px)] leading-[1.1] font-extrabold tracking-[-0.025em] transition-colors duration-150 group-hover:text-green-bright">
                    {featured.title}
                  </h2>
                  <p className="mb-5 text-[16px] leading-[1.6] text-muted">{featured.subtitle}</p>
                  <span className="inline-flex items-center gap-2 font-mono text-[13px] font-medium text-green transition-colors duration-150 group-hover:text-green-bright">
                    Read the guide
                    <ArrowRight className="size-4 transition-transform duration-150 group-hover:translate-x-0.5" aria-hidden />
                  </span>
                </div>
              </article>
            </a>
          </Reveal>
        </section>

        {/* Grid */}
        <section className="mx-auto max-w-[1120px] px-6 py-12">
          <div className="grid grid-cols-3 gap-5 max-[820px]:grid-cols-2 max-[560px]:grid-cols-1">
            {rest.map((post, i) => (
              <Reveal key={post.slug} delay={Math.min(i % 3, 2) * 80}>
                <BlogCard post={post} />
              </Reveal>
            ))}
          </div>
        </section>
      </main>
      <Footer />
    </>
  )
}
