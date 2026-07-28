import { Reveal } from "@/components/site/Reveal"
import { SectionHead } from "@/components/site/SectionHead"
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion"
import { faqs } from "@/lib/content"

export function Faq() {
  return (
    <section id="faq" className="mx-auto max-w-[1120px] px-6 py-28 max-[620px]:py-20">
      <SectionHead center eyebrow="faq" title="Questions, answered." />
      <Reveal className="mx-auto max-w-200">
        <Accordion type="single" collapsible>
          {faqs.map((faq) => (
            <AccordionItem key={faq.q} value={faq.q} className="border-white/[0.06]">
              <AccordionTrigger className="cursor-pointer px-1 py-5.5 text-[16.5px] font-semibold tracking-[-0.01em] hover:no-underline [&>svg]:text-green">
                {faq.q}
              </AccordionTrigger>
              <AccordionContent className="px-1 pb-6">
                <p
                  className="m-0 max-w-[70ch] text-[15px] leading-relaxed text-muted/90 [&_a]:text-green [&_a]:underline [&_a]:underline-offset-3 [&_code]:rounded-md [&_code]:border [&_code]:border-white/[0.06] [&_code]:bg-ink-800 [&_code]:px-1.75 [&_code]:py-0.5 [&_code]:font-mono [&_code]:text-[12px] [&_code]:text-green-dim"
                  dangerouslySetInnerHTML={{ __html: faq.html }}
                />
              </AccordionContent>
            </AccordionItem>
          ))}
        </Accordion>
      </Reveal>
    </section>
  )
}
