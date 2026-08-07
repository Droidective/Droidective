import { describe, expect, it } from "vitest"
import {
  batchLabel,
  breadcrumbs,
  childPath,
  currentPath,
  deletePrompt,
  folderNameToCreate,
  formatBytes,
  leafName,
  pasteLabel,
  pasteOperation,
  pruneSelection,
  runInOrder,
  selectAllToggle,
  summariseBatch,
  targetsFor,
  toggleSelected,
} from "@/lib/files"
import type { FileEntry } from "@/lib/wire"

function entry(name: string, isDir = false): FileEntry {
  return { name, isDir, size: 0, perms: isDir ? "drwxrwx---" : "-rw-rw----" }
}

const entries = [entry("DCIM", true), entry("Download", true), entry("note.txt")]

describe("currentPath", () => {
  it("anchors to /sdcard, which is all adb can read without su", () => {
    expect(currentPath([], false)).toBe("/sdcard")
    expect(currentPath(["DCIM", "Camera"], false)).toBe("/sdcard/DCIM/Camera")
  })

  it("browses from / in root mode", () => {
    expect(currentPath([], true)).toBe("/")
    expect(currentPath(["data", "local"], true)).toBe("/data/local")
  })
})

describe("childPath", () => {
  it("does not double the separator at the filesystem root", () => {
    // `/` + `/data` is the one join that goes wrong, and root mode starts there.
    expect(childPath("/", "data")).toBe("/data")
    expect(childPath("/sdcard", "DCIM")).toBe("/sdcard/DCIM")
  })
})

describe("leafName", () => {
  it("takes the last component", () => {
    expect(leafName("/sdcard/DCIM/photo.jpg")).toBe("photo.jpg")
    expect(leafName("/sdcard/DCIM/")).toBe("DCIM")
    expect(leafName("/")).toBe("/")
  })
})

describe("breadcrumbs", () => {
  it("leads with the root and carries the depth each crumb navigates to", () => {
    expect(breadcrumbs(["DCIM", "Camera"], false)).toEqual([
      { label: "sdcard", depth: 0 },
      { label: "DCIM", depth: 1 },
      { label: "Camera", depth: 2 },
    ])
  })

  it("names the root / in root mode", () => {
    expect(breadcrumbs([], true)).toEqual([{ label: "/", depth: 0 }])
  })
})

describe("the clipboard", () => {
  it("names one file and counts several", () => {
    expect(pasteLabel({ paths: ["/sdcard/note.txt"], isCut: false })).toBe("Paste note.txt")
    expect(pasteLabel({ paths: ["/sdcard/a", "/sdcard/b"], isCut: true })).toBe("Paste 2 items")
  })

  it("pastes a cut as a move and a copy as a copy", () => {
    expect(pasteOperation({ paths: [], isCut: true })).toBe("move")
    expect(pasteOperation({ paths: [], isCut: false })).toBe("copy")
  })
})

describe("targetsFor", () => {
  it("acts on the whole selection when the row is inside one", () => {
    const selection = new Set(["DCIM", "note.txt"])
    expect(targetsFor(entry("DCIM", true), selection, entries).map((e) => e.name)).toEqual([
      "DCIM",
      "note.txt",
    ])
  })

  it("acts on the one row when it is outside the selection", () => {
    const selection = new Set(["DCIM", "note.txt"])
    expect(targetsFor(entry("Download", true), selection, entries).map((e) => e.name)).toEqual([
      "Download",
    ])
  })

  it("acts on the one row when it is the only thing selected", () => {
    // Right-clicking your single checked row and getting a batch operation
    // would be a surprise on Delete.
    const selection = new Set(["DCIM"])
    expect(targetsFor(entry("DCIM", true), selection, entries).map((e) => e.name)).toEqual(["DCIM"])
  })
})

describe("selection", () => {
  it("toggles in and out", () => {
    expect([...toggleSelected(new Set(), "a")]).toEqual(["a"])
    expect([...toggleSelected(new Set(["a"]), "a")]).toEqual([])
  })

  it("selects all, then clears once everything is chosen", () => {
    expect([...selectAllToggle(new Set(), entries)]).toEqual(["DCIM", "Download", "note.txt"])
    expect([...selectAllToggle(new Set(entries.map((e) => e.name)), entries)]).toEqual([])
  })

  it("selects all rather than clearing when only some are chosen", () => {
    expect(selectAllToggle(new Set(["DCIM"]), entries).size).toBe(3)
  })

  it("does not offer to clear an empty folder", () => {
    expect([...selectAllToggle(new Set(), [])]).toEqual([])
  })

  it("drops names that are no longer in the folder", () => {
    // What a refresh after a delete leaves behind; a stale name would put the
    // selection bar's count out.
    expect([...pruneSelection(new Set(["DCIM", "gone.txt"]), entries)]).toEqual(["DCIM"])
  })
})

describe("messages", () => {
  it("names one target and counts several", () => {
    expect(batchLabel(["note.txt"])).toBe("note.txt")
    expect(batchLabel(["a", "b", "c"])).toBe("3 items")
  })

  it("says what delete is about to remove", () => {
    expect(deletePrompt([entry("note.txt")])).toBe("Delete note.txt? This can't be undone.")
    expect(deletePrompt(entries)).toBe("Delete 3 items? This can't be undone.")
  })
})

describe("folderNameToCreate", () => {
  it("trims, and refuses a name that is only whitespace", () => {
    expect(folderNameToCreate("  New Folder  ")).toBe("New Folder")
    expect(folderNameToCreate("   ")).toBeNull()
    expect(folderNameToCreate("")).toBeNull()
  })
})

describe("runInOrder", () => {
  it("stops at the first refusal rather than carrying on", async () => {
    // Deleting five files where the second is not yours should stop at the
    // second — not delete the other three and then report a mixed bag.
    const ran: string[] = []
    const call = (name: string, ok: boolean) => async () => {
      await Promise.resolve()
      ran.push(name)
      return { ok, message: name }
    }

    const results = await runInOrder([
      call("a", true),
      call("b", false),
      call("c", true),
    ])

    expect(ran).toEqual(["a", "b"])
    expect(results.map((result) => result.message)).toEqual(["a", "b"])
  })

  it("runs one at a time, not all at once", async () => {
    let live = 0
    let peak = 0
    const call = () => async () => {
      live += 1
      peak = Math.max(peak, live)
      await Promise.resolve()
      live -= 1
      return { ok: true }
    }

    await runInOrder([call(), call(), call()])
    expect(peak).toBe(1)
  })

  it("has nothing to do with an empty list", async () => {
    expect(await runInOrder([])).toEqual([])
  })
})

describe("summariseBatch", () => {
  it("reports the first failure rather than a count", () => {
    const outcome = summariseBatch(
      [
        { ok: true, message: "Deleted" },
        { ok: false, message: "Permission denied" },
      ],
      "Deleted 3 items",
    )
    expect(outcome).toEqual({ ok: false, message: "Permission denied" })
  })

  it("reports the batch when every item worked", () => {
    expect(summariseBatch([{ ok: true, message: "Deleted" }], "Deleted 3 items")).toEqual({
      ok: true,
      message: "Deleted 3 items",
    })
  })

  it("treats nothing to do as done", () => {
    expect(summariseBatch([], "Deleted").ok).toBe(true)
  })
})

describe("formatBytes", () => {
  it("reads the way the Mac's byte formatter does", () => {
    expect(formatBytes(0)).toBe("0 bytes")
    expect(formatBytes(512)).toBe("512 bytes")
    expect(formatBytes(1000)).toBe("1 KB")
    expect(formatBytes(1_234_567)).toBe("1.2 MB")
    expect(formatBytes(340_000_000)).toBe("340 MB")
    expect(formatBytes(2_500_000_000)).toBe("2.5 GB")
  })

  it("does not print a size for a directory row's zero", () => {
    expect(formatBytes(-1)).toBe("0 bytes")
    expect(formatBytes(Number.NaN)).toBe("0 bytes")
  })
})
