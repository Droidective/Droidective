import { BlogCard } from "@/components/site/BlogCard"
import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { Button } from "@/components/ui/button"
import { posts } from "@/lib/blogPosts"

/** Landing-page teaser linking to the full /blog/ index. */
export function Blog() {
  const latest = posts.slice(0, 3)
  return (
    <section id="blog" className="mx-auto max-w-[1120px] px-6 py-26 max-[620px]:py-18">
      <SectionHead center eyebrow="blog" title="Guides &amp; deep dives.">
        Role-by-role workflows for debugging Android &amp; React Native on a Mac — written in-house, no terminal
        required.
      </SectionHead>
      <div className="grid grid-cols-3 gap-5 max-[940px]:grid-cols-2 max-[620px]:grid-cols-1">
        {latest.map((post, i) => (
          <Reveal key={post.slug} delay={Math.min(i, 2) * 80}>
            <BlogCard post={post} surface="home-teaser" />
          </Reveal>
        ))}
      </div>
      <div className="mt-11 text-center">
        <Button
          asChild
          variant="outline"
          className="h-auto rounded-xl border-border-2 bg-white/4 px-5 py-3 text-[15px] font-semibold hover:bg-white/8"
        >
          <a href="/blog/" data-blog-cta="home-read-blog">
            Read the blog →
          </a>
        </Button>
      </div>
    </section>
  )
}
