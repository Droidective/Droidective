import { invoke } from "@tauri-apps/api/core"

import type { EditState } from "@/lib/video-edit"
import { suggestedName, wireOptions } from "@/lib/video-edit"

/**
 * The video editor's calls.
 *
 * ffmpeg lives in the daemon, the dialogs and the file reading live in the Rust
 * process, and the webview has neither — its capability file stays at
 * `core:default`, so a video reaches the player as bytes rather than as a path
 * it could open for itself.
 */

/** Every container the editor opens. Served, so both apps take one list. */
export function videoFormats(): Promise<string[]> {
  return invoke<string[]>("video_formats")
}

/**
 * One rung of the playback ladder.
 *
 * The client walks it rather than the daemon, because the only way to know
 * whether a file plays here is to hand it to a `<video>` and see. A remux is a
 * file copy's worth of work and fixes the common case; a transcode is for what
 * it cannot.
 */
export function videoProxy(path: string, mode: "remux" | "transcode"): Promise<string> {
  return invoke<string>("video_proxy", { path, mode })
}

export function removeVideoProxy(path: string): Promise<void> {
  return invoke("remove_video_proxy", { path })
}

/**
 * The bytes of a video, for the player. Refused past the preview ceiling.
 *
 * Returned as an `ArrayBuffer` rather than a `Uint8Array`: a view over a
 * possibly-shared buffer is not a `BlobPart`, and the caller only ever wraps it
 * in a `Blob`.
 */
export function readVideo(path: string): Promise<ArrayBuffer> {
  return invoke<number[]>("read_video", { path }).then((bytes) => Uint8Array.from(bytes).buffer as ArrayBuffer)
}

/**
 * Applies the edit, asking where the result should go.
 *
 * The export always reads the **original**, never the proxy, so a file that had
 * to be transcoded to play loses nothing in the saved result — the Mac makes
 * the same promise, and it is why trim points chosen against a proxy carry over
 * unchanged: both share one timeline.
 */
export function exportVideo(path: string, edit: EditState): Promise<string | null> {
  return invoke<string | null>("export_video", {
    path,
    suggestedName: suggestedName(path, edit.format),
    extension: edit.format,
    options: wireOptions(edit),
  })
}
