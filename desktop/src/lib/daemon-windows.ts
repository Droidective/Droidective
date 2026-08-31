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
export function openWorkspaceWindow(serial: string | null): Promise<string> {
  return invoke("open_workspace_window", { serial })
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
