/**
 * Screen recording's five verbs, plus the two things this process does with
 * the file afterwards.
 *
 * The session lives in the daemon, so this side holds no recording state of
 * its own — which is what lets the screen be closed and reopened mid-recording
 * and still find out what is running.
 */

import { invoke } from "@tauri-apps/api/core"
import type { ManagedToolEntry } from "@/lib/managed-tools"

export interface RecordStatus {
  recording: boolean
  paused: boolean
  serial: string | null
  /** Seconds of video captured, across every segment. */
  elapsedSeconds: number
  segments: number
  /**
   * False when ffmpeg is not installed. Asked before the button is pressed so
   * the screen can offer the download rather than failing into it.
   */
  ffmpegReady: boolean
}

export interface StoppedRecording {
  /** A temporary file. Nothing is kept until `saveRecording` says so. */
  path: string
  durationSeconds: number
  sizeBytes: number
}

/** The knobs the daemon takes. The time limit is enforced on this side. */
export interface RecordWireOptions {
  maxSize: number
  bitRateMbps: number
  maxFps: number
}

export function recordStatus(): Promise<RecordStatus> {
  return invoke("record_status")
}

export function recordStart(serial: string, options: RecordWireOptions): Promise<RecordStatus> {
  return invoke("record_start", { serial, options })
}

export function recordPause(): Promise<RecordStatus> {
  return invoke("record_pause")
}

export function recordResume(options: RecordWireOptions): Promise<RecordStatus> {
  return invoke("record_resume", { options })
}

export function recordStop(): Promise<StoppedRecording> {
  return invoke("record_stop")
}

/** Moves the finished file into the folder every capture lands in. */
export function saveRecording(path: string, name: string): Promise<string> {
  return invoke("save_recording", { path, name })
}

/** Throws the finished file away. Best-effort — it is in a temp directory. */
export function discardRecording(path: string): Promise<void> {
  return invoke("discard_recording", { path })
}

/** Settings ▸ Tools: what this host can download, and what is on disk. */
export function managedToolList(): Promise<{ tools: ManagedToolEntry[] }> {
  return invoke("managed_tool_list")
}

export function managedToolInstall(id: string): Promise<{ tools: ManagedToolEntry[] }> {
  return invoke("managed_tool_install", { id })
}

export function managedToolRemove(id: string): Promise<{ tools: ManagedToolEntry[] }> {
  return invoke("managed_tool_remove", { id })
}
