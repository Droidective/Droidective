/**
 * APK Studio's tabs, as a table.
 *
 * A table rather than markup so the set is one thing to read and one thing to
 * test against the registry: each tab is a feature the hub folded in, and a tab
 * that named an id the registry does not absorb would be a tab the Mac's studio
 * does not have.
 */

/** Which tab is showing. */
export type StudioTab = "inspect" | "decompile" | "sign"

export interface StudioTabDef {
  id: StudioTab
  title: string
  /**
   * The registry feature this tab *is* — the same screen the standalone
   * feature shows, handed the studio's APK.
   */
  featureID: string
}

/**
 * In the order the Mac's studio shows them, which is the order the work
 * happens in: read it, take it apart, then sign what you built.
 */
export const STUDIO_TABS: readonly StudioTabDef[] = [
  { id: "inspect", title: "Inspect", featureID: "apk-inspector" },
  { id: "decompile", title: "Decompile", featureID: "apk-decompile" },
  { id: "sign", title: "Sign", featureID: "apk-sign" },
]

/** The hub's own feature id. */
export const APK_STUDIO_ID = "apk-studio"
