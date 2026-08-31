import { describe, expect, it } from "vitest"

import {
  classifyDrop,
  droppedLabel,
  extensionOf,
  fileName,
  isInstallable,
  type DropContext,
} from "@/lib/file-drop"

function context(over: Partial<DropContext> = {}): DropContext {
  return { activeFeature: null, explorerDirectory: null, serials: ["emulator-5554"], ...over }
}

describe("extensionOf", () => {
  /**
   * Both separators, because the path comes from the *host*: a Windows drop
   * carries backslashes, and splitting on `/` alone reads the whole path as one
   * name and finds no extension in it.
   */
  it("reads the extension from either platform's path", () => {
    expect(extensionOf("/Users/me/app.apk")).toBe("apk")
    expect(extensionOf(String.raw`C:\Users\me\app.APK`)).toBe("apk")
  })

  it("has nothing to say about a file with no extension", () => {
    expect(extensionOf("/Users/me/README")).toBe("")
    expect(extensionOf("")).toBe("")
  })

  /** A dotfile is not an extension — `.gitignore` is a name. */
  it("does not mistake a dotfile for an extension", () => {
    expect(extensionOf("/Users/me/.gitignore")).toBe("")
  })
})

describe("isInstallable", () => {
  it("accepts every format the installer takes", () => {
    for (const name of ["a.apk", "a.apks", "a.xapk", "a.apkm", "a.aab"]) {
      expect(isInstallable(`/tmp/${name}`), name).toBe(true)
    }
  })

  it("refuses anything else", () => {
    for (const name of ["a.zip", "a.txt", "a.jar", "apk", "a.apk.txt"]) {
      expect(isInstallable(`/tmp/${name}`), name).toBe(false)
    }
  })
})

describe("classifyDrop", () => {
  /**
   * Installables win wherever they land, as they do on the Mac: dropping an
   * APK on the window installs it whatever is on screen, which is the whole
   * appeal of the gesture.
   */
  it("installs a package dropped anywhere", () => {
    expect(classifyDrop(["/tmp/app.apk"], context())).toEqual({
      kind: "install",
      paths: ["/tmp/app.apk"],
    })
    expect(
      classifyDrop(["/tmp/app.aab"], context({ activeFeature: "logcat" })).kind,
    ).toBe("install")
  })

  /** A mixed drop installs the packages rather than refusing the whole thing. */
  it("takes the installables out of a mixed drop", () => {
    expect(classifyDrop(["/tmp/notes.txt", "/tmp/app.apk"], context())).toEqual({
      kind: "install",
      paths: ["/tmp/app.apk"],
    })
  })

  it("pushes anything else onto the File Explorer's directory", () => {
    const action = classifyDrop(
      ["/tmp/notes.txt"],
      context({ activeFeature: "file-explorer", explorerDirectory: "/sdcard/Download" }),
    )
    expect(action).toEqual({
      kind: "push",
      paths: ["/tmp/notes.txt"],
      destination: "/sdcard/Download",
    })
  })

  /**
   * A file dropped on the logcat has no destination, and inventing one would
   * mean picking a directory on somebody else's device — so it says what to do
   * instead of guessing.
   */
  it("refuses a plain file with nowhere to put it", () => {
    const action = classifyDrop(["/tmp/notes.txt"], context({ activeFeature: "logcat" }))
    expect(action.kind).toBe("ignore")
    expect(action.kind === "ignore" && action.reason).toContain("File Explorer")
  })

  it("refuses the explorer with no directory read yet", () => {
    expect(
      classifyDrop(["/tmp/notes.txt"], context({ activeFeature: "file-explorer" })).kind,
    ).toBe("ignore")
  })

  /** Both actions need a device, and the message says which is missing. */
  it("refuses everything with no device", () => {
    const action = classifyDrop(["/tmp/app.apk"], context({ serials: [] }))
    expect(action.kind).toBe("ignore")
    expect(action.kind === "ignore" && action.reason).toContain("device")
  })

  it("refuses an empty drop", () => {
    expect(classifyDrop([], context()).kind).toBe("ignore")
    expect(classifyDrop(["   "], context()).kind).toBe("ignore")
  })
})

describe("fileName and droppedLabel", () => {
  it("names one file and counts several", () => {
    expect(fileName("/tmp/dir/app.apk")).toBe("app.apk")
    expect(fileName(String.raw`C:\dir\app.apk`)).toBe("app.apk")
    expect(droppedLabel(["/tmp/app.apk"])).toBe("app.apk")
    expect(droppedLabel(["/a.txt", "/b.txt", "/c.txt"])).toBe("3 files")
  })
})
