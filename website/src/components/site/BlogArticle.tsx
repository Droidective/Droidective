import { Inline, type Block } from "@/lib/markdown"

/** Renders a parsed blog body. Column width is tuned for long-form reading. */
export function BlogArticle({ blocks }: { blocks: Block[] }) {
  return (
    <div className="mx-auto max-w-[720px]">
      {blocks.map((block, idx) => {
        switch (block.kind) {
          case "heading":
            return (
              <h2
                key={idx}
                className="mt-14 mb-4 scroll-mt-24 text-[clamp(22px,3vw,29px)] leading-[1.15] font-extrabold tracking-[-0.025em] text-text first:mt-0"
              >
                <Inline text={block.text} />
              </h2>
            )
          case "para":
            return (
              <p key={idx} className="mb-5 text-[17.5px] leading-[1.8] text-text/85">
                <Inline text={block.text} />
              </p>
            )
          case "list":
            return (
              <ul
                key={idx}
                className="mb-6 list-disc space-y-2.5 pl-5.5 text-[17.5px] leading-[1.7] text-text/85 marker:text-green"
              >
                {block.items.map((item, itemIdx) => (
                  <li key={itemIdx} className="pl-1">
                    <Inline text={item} />
                  </li>
                ))}
              </ul>
            )
          case "callout":
            return (
              <div
                key={idx}
                className="my-8 rounded-xl border border-amber/30 bg-amber/8 px-5 py-4 text-[16px] leading-[1.7] text-text/90"
              >
                <Inline text={block.text} />
              </div>
            )
          case "figure":
            return (
              <figure key={idx} className="my-9">
                {block.isVideo ? (
                  <video
                    className="w-full rounded-xl border border-border-2 shadow-[0_20px_50px_-20px_rgba(0,0,0,0.6)]"
                    src={block.src}
                    autoPlay
                    loop
                    muted
                    playsInline
                    aria-label={block.alt}
                  />
                ) : (
                  <img
                    className="w-full rounded-xl border border-border-2 shadow-[0_20px_50px_-20px_rgba(0,0,0,0.6)]"
                    src={block.src}
                    alt={block.alt}
                    loading="lazy"
                  />
                )}
                {block.caption && (
                  <figcaption className="mt-3 text-center text-[13.5px] text-faint">
                    <Inline text={block.caption} />
                  </figcaption>
                )}
              </figure>
            )
          default:
            return null
        }
      })}
    </div>
  )
}
