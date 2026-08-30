import { useCallback } from "react"
import type { WorkspaceController } from "@/hooks/useWorkspace"
import type { Hotkey } from "@/lib/hotkeys"
import type { LayoutState } from "@/lib/layout"
import { clampZoomStep, DEFAULT_ZOOM_STEP } from "@/lib/zoom"

/**
 * The preferences, as opposed to the arrangement.
 *
 * `useLayoutEditors` in `useWorkspace` changes how the window is *laid out*;
 * these are
 * settings that happen to be persisted in the same place — the device bar's Run
 * on all, the sidebar's mode, background mode, what the tray lists, and the
 * Quick Actions panel's three. Split because the two grew past one readable
 * function, and this is the seam.
 */
export function usePreferenceEditors(
  setLayout: React.Dispatch<React.SetStateAction<LayoutState>>,
): Pick<
  WorkspaceController,
  | "setRunOnAll"
  | "setSidebarAutoHide"
  | "setKeepRunningInBackground"
  | "setTrayItem"
  | "setQuickPanelAction"
  | "setQuickPanelCloseAfterRun"
  | "setQuickPanelHotkey"
  | "zoom"
> {
  return {
    setRunOnAll: useCallback(
      (runOnAll: boolean) => {
        setLayout((current) => ({ ...current, runOnAll }))
      },
      [setLayout],
    ),
    setSidebarAutoHide: useCallback(
      (sidebarAutoHide: boolean) => {
        setLayout((current) => ({ ...current, sidebarAutoHide }))
      },
      [setLayout],
    ),
    setKeepRunningInBackground: useCallback(
      (keepRunningInBackground: boolean) => {
        setLayout((current) => ({ ...current, keepRunningInBackground }))
      },
      [setLayout],
    ),
    setTrayItem: useCallback(
      (id: string, listed: boolean) => {
        setLayout((current) => ({
          ...current,
          trayItems: listed
            ? [...current.trayItems.filter((item) => item !== id), id]
            : current.trayItems.filter((item) => item !== id),
        }))
      },
      [setLayout],
    ),
    // Stored as the *hidden* set, like the catalog's: everything is in the
    // panel by default, so an action shipped later is there without a
    // migration having to notice it.
    setQuickPanelAction: useCallback(
      (id: string, shown: boolean) => {
        setLayout((current) => ({
          ...current,
          quickPanelHiddenIds: shown
            ? current.quickPanelHiddenIds.filter((item) => item !== id)
            : [...current.quickPanelHiddenIds.filter((item) => item !== id), id],
        }))
      },
      [setLayout],
    ),
    setQuickPanelCloseAfterRun: useCallback(
      (quickPanelCloseAfterRun: boolean) => {
        setLayout((current) => ({ ...current, quickPanelCloseAfterRun }))
      },
      [setLayout],
    ),
    setQuickPanelHotkey: useCallback(
      (quickPanelHotkey: Hotkey | null) => {
        setLayout((current) => ({ ...current, quickPanelHotkey }))
      },
      [setLayout],
    ),
    zoom: useCallback(
      (direction: -1 | 0 | 1) => {
        setLayout((current) => ({
          ...current,
          zoomStep:
            direction === 0 ? DEFAULT_ZOOM_STEP : clampZoomStep(current.zoomStep + direction),
        }))
      },
      [setLayout],
    ),
  }
}
