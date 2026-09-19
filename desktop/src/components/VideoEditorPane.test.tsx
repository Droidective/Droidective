import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

const { pickFile, videoFormats, exportVideo, readVideo, videoProxy, removeVideoProxy, show } =
  vi.hoisted(() => ({
    pickFile: vi.fn(),
    videoFormats: vi.fn(),
    exportVideo: vi.fn(),
    readVideo: vi.fn(),
    videoProxy: vi.fn(),
    removeVideoProxy: vi.fn(),
    show: vi.fn(),
  }))

vi.mock("@/lib/daemon", () => ({
  pickFile,
  asDaemonError: (thrown: unknown) => ({ code: "unknown", message: String(thrown), detail: null }),
}))
vi.mock("@/lib/daemon-video", () => ({
  videoFormats,
  exportVideo,
  readVideo,
  videoProxy,
  removeVideoProxy,
}))
vi.mock("@/hooks/useNotifications", () => ({ useNotifications: () => ({ show }) }))

const { VideoEditorPane } = await import("@/components/VideoEditorPane")

describe("VideoEditorPane", () => {
  beforeEach(() => {
    vi.clearAllMocks()
    videoFormats.mockResolvedValue(["mp4", "mkv"])
    pickFile.mockResolvedValue("/home/me/clip.mp4")
    readVideo.mockResolvedValue(new ArrayBuffer(8))
    exportVideo.mockResolvedValue("/home/me/Downloads/clip.gif")
    globalThis.URL.createObjectURL = vi.fn(() => "blob:clip")
    globalThis.URL.revokeObjectURL = vi.fn()
  })

  // The empty state's words are `VideoEditorView.emptyState`'s, not this
  // port's own: they name every edit the screen can make and say where a clip
  // comes from, which is the whole job of the one screen with nothing on it.
  it("asks before there is anything to edit, in the Mac's words", () => {
    render(<VideoEditorPane />)
    expect(screen.getByRole("button", { name: "Open video…" })).toBeDefined()
    expect(screen.getByText(/trim, rotate, crop, change speed, convert, and compress/u)).toBeDefined()
    expect(screen.getByText(/record one from Screen Record/u)).toBeDefined()
  })

  it("filters the open panel by the served list rather than one of its own", async () => {
    render(<VideoEditorPane />)
    fireEvent.click(screen.getByRole("button", { name: "Open video…" }))
    await waitFor(() => {
      expect(pickFile).toHaveBeenCalledWith("Video", ["mp4", "mkv"])
    })
  })

  it("shows the file once one is open", async () => {
    render(<VideoEditorPane />)
    fireEvent.click(screen.getByRole("button", { name: "Open video…" }))
    expect(await screen.findByText("clip.mp4")).toBeDefined()
  })

  it("offers the Mac's transform and output controls", async () => {
    render(<VideoEditorPane />)
    fireEvent.click(screen.getByRole("button", { name: "Open video…" }))
    await screen.findByText("clip.mp4")
    expect(screen.getByLabelText("Rotate left")).toBeDefined()
    expect(screen.getByLabelText("Rotate right")).toBeDefined()
    expect(screen.getByRole("button", { name: /Flip H/u })).toBeDefined()
    expect(screen.getByRole("button", { name: /Flip V/u })).toBeDefined()
    expect(screen.getByLabelText("Speed")).toBeDefined()
    expect(screen.getByLabelText("Format")).toBeDefined()
    expect(screen.getByLabelText("Compression")).toBeDefined()
  })

  it("sends the edit it was given, and reports where the file landed", async () => {
    render(<VideoEditorPane />)
    fireEvent.click(screen.getByRole("button", { name: "Open video…" }))
    await screen.findByText("clip.mp4")

    fireEvent.click(screen.getByLabelText("Rotate right"))
    fireEvent.change(screen.getByLabelText("Format"), { target: { value: "gif" } })
    fireEvent.click(screen.getByRole("button", { name: /Export/u }))

    await waitFor(() => {
      expect(exportVideo).toHaveBeenCalledWith(
        "/home/me/clip.mp4",
        expect.objectContaining({ rotationDegrees: 90, format: "gif" }),
      )
    })
    expect(show).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true, revealPath: "/home/me/Downloads/clip.gif" }),
    )
  })

  it("says nothing when the save dialog was dismissed", async () => {
    exportVideo.mockResolvedValue(null)
    render(<VideoEditorPane />)
    fireEvent.click(screen.getByRole("button", { name: "Open video…" }))
    await screen.findByText("clip.mp4")

    fireEvent.click(screen.getByRole("button", { name: /Export/u }))
    await waitFor(() => {
      expect(exportVideo).toHaveBeenCalledOnce()
    })
    // A cancelled dialog is a choice, not a failure worth a toast.
    expect(show).not.toHaveBeenCalled()
  })

  it("undoes a transform", async () => {
    render(<VideoEditorPane />)
    fireEvent.click(screen.getByRole("button", { name: "Open video…" }))
    await screen.findByText("clip.mp4")

    fireEvent.click(screen.getByLabelText("Rotate right"))
    fireEvent.click(screen.getByLabelText("Undo"))
    fireEvent.click(screen.getByRole("button", { name: /Export/u }))

    await waitFor(() => {
      expect(exportVideo).toHaveBeenCalledWith(
        "/home/me/clip.mp4",
        expect.objectContaining({ rotationDegrees: 0 }),
      )
    })
  })
})

describe("VideoEditorPane — what it says when it cannot show a picture", () => {
  beforeEach(() => {
    vi.clearAllMocks()
    videoFormats.mockResolvedValue(["mp4", "mkv"])
    pickFile.mockResolvedValue("/home/me/clip.mp4")
    globalThis.URL.createObjectURL = vi.fn(() => "blob:clip")
    globalThis.URL.revokeObjectURL = vi.fn()
  })

  it("reports a file it could not read at all", async () => {
    readVideo.mockRejectedValue(new Error("that video is 900 MB — too large to preview here"))
    render(<VideoEditorPane />)
    fireEvent.click(screen.getByRole("button", { name: "Open video…" }))
    expect(await screen.findByText(/too large to preview here/u)).toBeDefined()
  })
})
