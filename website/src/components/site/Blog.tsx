import { BlogCard } from "@/components/site/BlogCard"
import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { Button } from "@/components/ui/button"
import { posts } from "@/lib/blogPosts"

export function Blog() {
  const latest = posts.slice(0, 3)
  return (
    <section id="blog" className="mx-auto max-w-[1120px] px-6 py-28 max-[620px]:py-20">
      <SectionHead center eyebrow="blog" title="Guides &amp; deep dives.">
        Role-by-role workflows for debugging Android &amp; React Native on a Mac — written in-house, no terminal
        required.
      </SectionHead>
      <div className="grid grid-cols-3 gap-5 max-[940px]:grid-cols-2 max-[620px]:grid-cols-1">
        {latest.map((post, i) => (
          <Reveal key={post.slug} delay={Math.min(i, 2) * 60}>
            <BlogCard post={post} surface="home-teaser" />
          </Reveal>
        ))}
      </div>
      <div className="mt-12 text-center">
        <Button
          asChild
          variant="outline"
          className="h-auto rounded-xl border-white/[0.08] bg-white/[0.03] px-5 py-3 text-[14.5px] font-semibold transition-all duration-200 hover:border-white/[0.14] hover:bg-white/[0.06]"
        >
          <a href="/blog/" data-blog-cta="home-read-blog">
            Read the blog →
          </a>
        </Button>
      </div>
    </section>
  )
}
