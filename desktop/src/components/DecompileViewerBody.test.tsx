import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { DecompileViewerBody } from "@/components/DecompileViewerBody"
import type { DecompileFileText } from "@/lib/wire"

const source = { text: "class Foo { void bar() {} }", truncated: false, byteCount: 27 } as DecompileFileText

describe("the decompiled file viewer", () => {
  it("shows the source as it is when nothing is being searched for", () => {
    render(<DecompileViewerBody path="a/Foo.java" source={source} loading={false} find="" />)
    expect(document.querySelectorAll("mark")).toHaveLength(0)
    expect(screen.getByText(/class Foo/u)).toBeTruthy()
  })

  it("marks every occurrence of the find query", () => {
    render(<DecompileViewerBody path="a/Foo.java" source={source} loading={false} find="bar" />)
    expect(document.querySelectorAll("mark")).toHaveLength(1)
  })

  it("matches whatever the casing, and keeps the original", () => {
    render(<DecompileViewerBody path="a/Foo.java" source={source} loading={false} find="FOO" />)
    const marks = [...document.querySelectorAll("mark")].map((one) => one.textContent)
    expect(marks).toEqual(["Foo"])
  })

  it("says so rather than dumping bytes for a binary file", () => {
    // apktool copies assets through as they are, and a PNG rendered as text is
    // a screenful of noise.
    render(<DecompileViewerBody path="res/icon.png" source={source} loading={false} find="" />)
    expect(screen.getByText(/binary file/u)).toBeTruthy()
  })
})
