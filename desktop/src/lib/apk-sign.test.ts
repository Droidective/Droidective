import { describe, expect, it } from "vitest"

import { baseName, convertedApkName, signedApkName } from "@/lib/apk-sign"

describe("naming what a tool produces", () => {
  it("never gives the output the input's name", () => {
    // The whole reason this is a function: an output landing on the input's
    // path destroys the unsigned original, and there is no undo.
    expect(signedApkName("/tmp/app.apk")).toBe("app-signed.apk")
    expect(signedApkName("/tmp/app.apk")).not.toBe(baseName("/tmp/app.apk"))
  })

  it("keeps the extension where there is one", () => {
    expect(signedApkName("app.apk")).toBe("app-signed.apk")
    expect(signedApkName("release.APK")).toBe("release-signed.APK")
  })

  it("copes with a name that has no extension", () => {
    expect(signedApkName("app")).toBe("app-signed.apk")
    // A leading dot is the whole name, not an extension.
    expect(signedApkName(".hidden")).toBe(".hidden-signed.apk")
  })

  it("turns a bundle into a universal APK name", () => {
    expect(convertedApkName("/tmp/app.aab")).toBe("app-universal.apk")
    expect(convertedApkName("bundle")).toBe("bundle-universal.apk")
  })

  it("splits on either separator, because this ships on Windows too", () => {
    expect(baseName("/home/me/app.apk")).toBe("app.apk")
    expect(baseName("C:\\Users\\me\\app.apk")).toBe("app.apk")
    expect(baseName("app.apk")).toBe("app.apk")
  })
})
