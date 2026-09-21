import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { ReactotronImage } from "@/components/ReactotronImage"

const URI = "data:image/png;base64,iVBORw0KGgo="

describe("a logged image", () => {
  it("shows the picture, not the base64 behind it", () => {
    // This detail used to fall through to the JSON tree, which rendered the
    // data URI as text — for an event whose whole point is looking at it.
    render(<ReactotronImage uri={URI} />)
    expect(screen.getByRole("img").getAttribute("src")).toBe(URI)
  })

  it("says the preview is clickable, in the Mac's words", () => {
    render(<ReactotronImage uri={URI} />)
    expect(screen.getByTitle("Click to view full size")).toBeTruthy()
  })

  it("opens full size on a click, and closes again", () => {
    // A phone screenshot is taller than any detail pane, so the inline
    // preview is bounded and this is the way to the whole thing.
    render(<ReactotronImage uri={URI} caption="Home screen" />)
    fireEvent.click(screen.getByTitle("Click to view full size"))
    const overlay = screen.getByLabelText("Close the full-size image")
    expect(overlay).toBeTruthy()
    fireEvent.click(overlay)
    expect(screen.queryByLabelText("Close the full-size image")).toBeNull()
  })

  it("captions with the size when the client reported one", () => {
    render(<ReactotronImage uri={URI} caption="Home screen" width={1080} height={2400} />)
    expect(screen.getByText("Home screen · 1080×2400")).toBeTruthy()
  })

  it("uses the caption as the alt text, since that is what it describes", () => {
    render(<ReactotronImage uri={URI} caption="Home screen" />)
    expect(screen.getByAltText("Home screen")).toBeTruthy()
  })
})
