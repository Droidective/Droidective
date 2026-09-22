/**
 * The window registry, which lives in the Rust process.
 *
 * Not a daemon route: the daemon has no idea what a window is, and the
 * question — "which of *my* windows is already mirroring this device?" — is
 * about this app's own windows. The Rust process is where they all are, which
 * makes it the equivalent of the Mac's `AppCore`.
 */

import { invoke } from "@tauri-apps/api/core"
import { listen, type UnlistenFn } from "@tauri-apps/api/event"

import type { WindowClaim } from "@/lib/workspaces"

const CLAIMS_EVENT = "workspace://claims"
const CLOSE_FEATURE_EVENT = "workspace://close-feature"

/** What every window is holding, for a window that has just opened. */
export function workspaceClaims(): Promise<WindowClaim[]> {
  return invoke("workspace_claims")
}

/** Publish this window's device and open features; answers the new snapshot. */
export function publishClaim(
  label: string,
  claim: { serial: string | null; features: string[] },
): Promise<WindowClaim[]> {
  return invoke("publish_claim", { label, claim })
}

/** Drop this window's claim — its webview is going away. */
export function releaseClaim(label: string): Promise<void> {
  return invoke("release_claim", { label })
}

/** A new workspace window, optionally opening on a device. */
export function openWorkspaceWindow(
  serial: string | null,
  feature: string | null = null,
): Promise<string> {
  return invoke("open_workspace_window", { serial, feature })
}

/** Bring another window to the front. */
export function focusWorkspaceWindow(label: string): Promise<void> {
  return invoke("focus_workspace_window", { label })
}

/** Fires whenever any window's claim changes. */
export function onWorkspaceClaims(
  handler: (claims: WindowClaim[]) => void,
): Promise<UnlistenFn> {
  return listen<WindowClaim[]>(CLAIMS_EVENT, (event) => {
    handler(event.payload)
  })
}

/**
 * Ask the window that owns an exclusive feature to close it.
 *
 * Take Over closes the tab *there* first, so there is never a moment with two
 * live sessions against one device.
 */
export function requestCloseFeature(label: string, feature: string): Promise<void> {
  return invoke("request_close_feature", { label, feature })
}

/** Fires when another window asks this one to give a feature up. */
export function onCloseFeatureRequest(
  handler: (feature: string) => void,
): Promise<UnlistenFn> {
  return listen<string>(CLOSE_FEATURE_EVENT, (event) => {
    handler(event.payload)
  })
}

/**
 * Ask the native window for the platform's blur, and hear whether it took.
 *
 * Not a daemon route for the same reason the registry is not: a window's
 * appearance is the Rust process's business, and the daemon has never heard of
 * windows.
 */
export function setWindowBlur(label: string, enabled: boolean): Promise<boolean> {
  return invoke("set_window_blur", { label, enabled })
}

/** Whether this platform has a window blur an application can ask for. */
export function windowBlurSupported(): Promise<boolean> {
  return invoke("window_blur_supported")
}

/** Where the pop-out mirrors could be tiled, and which windows they are. */
export interface MirrorWindowLayout {
  /**
   * The usable area of the screen the first pop-out is on, or null when there
   * are none — physical pixels, with the taskbar and the dock outside it.
   */
  area: { x: number; y: number; width: number; height: number } | null
  /** Pop-out window labels, in serial order. */
  labels: string[]
}

export function mirrorWindowLayout(): Promise<MirrorWindowLayout> {
  return invoke<MirrorWindowLayout>("mirror_window_layout")
}

/**
 * Put each named window where it was told.
 *
 * The arithmetic is `mirror-wall.ts`' `windowFrames`, tested beside the grid
 * the wall itself draws — this only applies it.
 */
export function setWindowFrames(
  frames: { label: string; x: number; y: number; width: number; height: number }[],
): Promise<void> {
  return invoke<void>("set_window_frames", { frames })
}
