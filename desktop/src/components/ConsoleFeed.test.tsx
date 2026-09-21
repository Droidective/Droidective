import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { ConsoleFeed } from "@/components/ConsoleFeed"
import type { ConsoleRow } from "@/lib/console-feed"

function row(id: number, text: string): ConsoleRow {
  return {
    id,
    level: "info",
    type: "log",
    args: [],
    text,
    timestamp: 0,
    source: null,
    local: false,
  }
}

const rows = [row(1, "loading user"), row(2, "User saved")]

function feed(find: string, currentMatch: number | null = null) {
  render(
    <ConsoleFeed
      rows={rows}
      empty={false}
      problem={null}
      connection="connected"
      targetCount={1}
      find={find}
      currentMatch={currentMatch}
    />,
  )
}

describe("find highlighting in the feed", () => {
  it("marks every occurrence, whatever its casing", () => {
    feed("user")
    const marks = screen.getAllByText(/^user$/iu)
    expect(marks.map((one) => one.textContent)).toEqual(["user", "User"])
  })

  it("marks nothing without a query", () => {
    // Opening the bar and typing nothing must not light up the whole feed.
    feed("")
    expect(document.querySelectorAll("mark")).toHaveLength(0)
  })

  it("gives the current match its own shade, not just any match", () => {
    feed("user", 2)
    const marks = [...document.querySelectorAll("mark")]
    expect(marks).toHaveLength(2)
    // The row the arrows are on is amber; the other match stays yellow.
    expect(marks[0]?.className).toContain("bg-yellow-300")
    expect(marks[1]?.className).toContain("bg-amber-400")
  })

  it("keeps the row's text intact around the highlight", () => {
    // Split into runs and rejoined, so the row must still read as one line
    // rather than losing the text either side of what matched.
    feed("user")
    expect(document.querySelector('[data-row="1"]')?.textContent).toContain("loading user")
  })
})
