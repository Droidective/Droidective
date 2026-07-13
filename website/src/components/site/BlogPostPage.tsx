import { useEffect, useRef } from "react"

import { ArrowLeft, ArrowRight, Clock, Download, Star } from "lucide-react"

import { BlogArticle } from "@/components/site/BlogArticle"
import { BlogHeader } from "@/components/site/BlogHeader"
import { Footer } from "@/components/site/Footer"
import { Button } from "@/components/ui/button"
import { track } from "@/lib/analytics"
import { getPost, posts } from "@/lib/blogPosts"
import { DOWNLOAD_URL, GITHUB_URL } from "@/lib/content"

export function BlogPostPage({ slug }: { slug: string }) {
  const post = getPost(slug)
  const endRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!post) {
      track("blog_post_not_found", { slug })
      return
    }
    track("blog_post_viewed", {
      slug: post.slug,
      role: post.role,
      title: post.title,
      read_minutes: post.readMinutes,
    })

    const el = endRef.current
    if (!el || typeof IntersectionObserver === "undefined") return
    let done = false
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting && !done) {
            done = true
            track("blog_post_completed", { slug: post.slug, role: post.role })
            observer.disconnect()
          }
        }
      },
      { threshold: 0.4 },
    )
    observer.observe(el)
    return () => observer.disconnect()
  }, [post, slug])

  if (!post) {
    return (
      <>
        <BlogHeader />
        <main className="mx-auto max-w-[720px] px-6 py-32 text-center">
          <h1 className="mb-4 text-3xl font-extrabold tracking-[-0.02em]">Post not found</h1>
          <p className="mb-8 text-muted">That article doesn’t exist (or moved).</p>
          <a href="/blog/" className="font-mono text-sm text-green hover:text-green-bright">
            ← all posts
          </a>
        </main>
        <Footer />
      </>
    )
  }

  const more = posts.filter((other) => other.slug !== post.slug).slice(0, 3)

  return (
    <>
      <BlogHeader />
      <main>
        <article className="px-6 pt-14 pb-4 max-[620px]:pt-9">
          <div className="mx-auto max-w-[720px]">
            <p className="mb-6 font-mono text-[12.5px] text-faint">
              <a href="/blog/" className="transition-colors duration-150 hover:text-green">
                Blog
              </a>
              <span className="mx-2 opacity-50">/</span>
              <span className="text-muted">{post.role}</span>
            </p>
            <div className="mb-5 flex flex-wrap items-center gap-3 font-mono text-[12.5px] text-muted">
              <span className="rounded-full border border-green/20 bg-green/8 px-2.5 py-1 font-medium text-green">
                {post.role}
              </span>
              <span>{post.dateLabel}</span>
              <span className="inline-flex items-center gap-1.5">
                <Clock className="size-3.5" aria-hidden />
                {post.readMinutes} min read
              </span>
            </div>
            <h1 className="mb-5 text-[clamp(30px,5vw,46px)] leading-[1.06] font-extrabold tracking-[-0.035em]">
              {post.title}
            </h1>
            <p className="mb-2 text-[clamp(18px,2.2vw,21px)] leading-[1.5] text-muted">{post.subtitle}</p>
          </div>
        </article>

        <div className="px-6 pb-4">
          <BlogArticle blocks={post.blocks} />
        </div>

        {/* End CTA */}
        <div className="px-6 py-12">
          <div
            ref={endRef}
            className="mx-auto max-w-[720px] rounded-2xl border border-border bg-linear-to-b from-green/6 to-white/0 p-8 text-center max-[620px]:p-6"
          >
            <h2 className="mb-2.5 text-2xl font-extrabold tracking-[-0.02em]">Try Droidective</h2>
            <p className="mx-auto mb-6 max-w-[46ch] text-[15.5px] text-muted">
              Free, open source, and native to macOS. 56 Android &amp; React Native debugging tools, one keystroke
              away.
            </p>
            <div className="flex flex-wrap justify-center gap-3.25">
              <Button
                asChild
                size="lg"
                className="h-auto rounded-xl px-5 py-3 text-[15px] font-bold shadow-glow transition-transform duration-150 hover:-translate-y-px hover:bg-green-bright"
              >
                <a href={DOWNLOAD_URL} data-dl="blog-post" data-blog-cta="post-download" data-blog-slug={post.slug}>
                  <Download aria-hidden />
                  Download for macOS
                </a>
              </Button>
              <Button
                asChild
                variant="outline"
                size="lg"
                className="h-auto rounded-xl border-border-2 bg-white/4 px-5 py-3 text-[15px] font-semibold transition-transform duration-150 hover:-translate-y-px hover:bg-white/8"
              >
                <a href={GITHUB_URL} data-blog-cta="post-github" data-blog-slug={post.slug}>
                  <Star aria-hidden />
                  Star on GitHub
                </a>
              </Button>
            </div>
          </div>
        </div>

        {/* More from the blog */}
        <section className="border-t border-border px-6 py-16">
          <div className="mx-auto max-w-[1120px]">
            <div className="mb-8 flex items-center justify-between gap-4">
              <h2 className="text-xl font-bold tracking-[-0.01em]">More from the blog</h2>
              <a
                href="/blog/"
                className="inline-flex items-center gap-1.5 font-mono text-[13px] text-green transition-colors duration-150 hover:text-green-bright"
              >
                All posts
                <ArrowRight className="size-3.5" aria-hidden />
              </a>
            </div>
            <div className="grid grid-cols-3 gap-4 max-[820px]:grid-cols-2 max-[560px]:grid-cols-1">
              {more.map((other) => (
                <a
                  key={other.slug}
                  href={`/blog/${other.slug}/`}
                  className="group block h-full"
                  data-blog-related={other.slug}
                  data-blog-from={post.slug}
                >
                  <div className="flex h-full flex-col rounded-xl border border-border bg-linear-to-b from-white/2 to-white/0 p-5 transition-[transform,border-color] duration-150 group-hover:-translate-y-[3px] group-hover:border-green/30 motion-reduce:group-hover:translate-y-0">
                    <span className="mb-2.5 font-mono text-[11.5px] font-medium tracking-[0.04em] text-green">
                      {other.role}
                    </span>
                    <h3 className="text-[15.5px] leading-[1.35] font-semibold tracking-[-0.01em]">{other.title}</h3>
                  </div>
                </a>
              ))}
            </div>
            <div className="mt-10">
              <a
                href="/blog/"
                className="inline-flex items-center gap-2 font-mono text-[13px] text-muted transition-colors duration-150 hover:text-green"
              >
                <ArrowLeft className="size-3.5" aria-hidden />
                Back to all posts
              </a>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  )
}
