import { About } from "@/components/site/About"
import { Blog } from "@/components/site/Blog"
import { Changelog } from "@/components/site/Changelog"
import { Contribute } from "@/components/site/Contribute"
import { Faq } from "@/components/site/Faq"
import { Features } from "@/components/site/Features"
import { FinalCta } from "@/components/site/FinalCta"
import { Footer } from "@/components/site/Footer"
import { Hero } from "@/components/site/Hero"
import { HowItWorks } from "@/components/site/HowItWorks"
import { Nav } from "@/components/site/Nav"
import { Problems } from "@/components/site/Problems"
import { ProductShowcase } from "@/components/site/ProductShowcase"
import { Screenshots } from "@/components/site/Screenshots"
import { TrustStrip } from "@/components/site/TrustStrip"
import { UseCases } from "@/components/site/UseCases"

export default function App() {
  return (
    <div className="noise">
      <a
        href="#features"
        className="absolute top-0 -left-[999px] z-200 rounded-br-[10px] bg-green px-4 py-2.5 font-bold text-ink-900 focus:left-0"
      >
        Skip to content
      </a>
      <Nav />
      <main>
        <Hero />
        <TrustStrip />
        <Problems />
        <Features />
        <ProductShowcase />
        <Screenshots />
        <HowItWorks />
        <UseCases />
        <Blog />
        <Changelog />
        <Faq />
        <Contribute />
        <About />
        <FinalCta />
      </main>
      <Footer />
    </div>
  )
}
