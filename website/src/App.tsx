import { About } from "@/components/site/About"
import { Blog } from "@/components/site/Blog"
import { Changelog } from "@/components/site/Changelog"
import { Comparison } from "@/components/site/Comparison"
import { Contribute } from "@/components/site/Contribute"
import { DemoMoment } from "@/components/site/DemoMoment"
import { Faq } from "@/components/site/Faq"
import { FeatureExplorer } from "@/components/site/FeatureExplorer"
import { FinalCta } from "@/components/site/FinalCta"
import { Footer } from "@/components/site/Footer"
import { FreeValue } from "@/components/site/FreeValue"
import { Hero } from "@/components/site/Hero"
import { HowItWorks } from "@/components/site/HowItWorks"
import { McpSpotlight } from "@/components/site/McpSpotlight"
import { Nav } from "@/components/site/Nav"
import { TrustStrip } from "@/components/site/TrustStrip"
import { UseCaseMoments } from "@/components/site/UseCaseMoments"
import { WorkflowTabs } from "@/components/site/WorkflowTabs"

/*
 * Section order is a deliberate rhythm — no two adjacent sections share a
 * shape. Interactive → text → immersive video → table → bold type → list.
 * Spacing tiers: py-32 immersive, py-24 medium, py-16 compact.
 */
export default function App() {
  return (
    <div className="noise">
      <a
        href="#workflows"
        className="absolute top-0 -left-[999px] z-200 rounded-br-[10px] bg-green px-4 py-2.5 font-bold text-ink-900 focus:left-0"
      >
        Skip to content
      </a>
      <Nav />
      <main>
        <Hero />
        <TrustStrip />
        <WorkflowTabs />
        <McpSpotlight />
        <DemoMoment />
        <Comparison />
        <FreeValue />
        <FeatureExplorer />
        <UseCaseMoments />
        <HowItWorks />
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
