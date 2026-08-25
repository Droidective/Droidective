/**
 * The Mirror Wall's layout and selection maths.
 *
 * A port of ADBKit's `MirrorWall`, which the Mac uses, and the tests assert the
 * same numbers its Swift suite does. Pure — no device, no decoder, no view —
 * which is what lets the grid shape, the per-tile quality and the selection cap
 * be tested here at all.
 *
 * Ported rather than served by the daemon because it is arithmetic: a round
 * trip to ask how many columns to draw would be a network call to avoid
 * duplicating twenty lines, and the layout has to answer on every resize.
 */

/**
 * How many devices one wall streams at once.
 *
 * Every tile is a separate device-side H.264 encoder and a separate decoder in
 * this webview, so the cap is a real ceiling rather than a UI convenience.
 */
export const MAXIMUM_DEVICES = 6

/**
 * Narrowest tile that still shows a usable phone screen. Below this the auto
 * grid drops a column instead of shrinking further.
 */
export const MINIMUM_TILE_WIDTH = 260

/** What one tile asks the device-side server for. */
export interface Quality {
  /** scrcpy `max_size` — longest side in px. */
  maxSize: number
  /** scrcpy `max_fps` — 0 leaves the device uncapped. */
  maxFps: number
}

/**
 * The single mirror's quality — what one tile gets, so a one-device wall looks
 * exactly like the Mirror Screen tab.
 */
export const FULL_QUALITY: Quality = { maxSize: 1280, maxFps: 0 }

/**
 * Quality for each tile of a `tiles`-tile wall.
 *
 * A tile is a fraction of the pane, so full-mirror resolution is decode work
 * nobody can see. Frame rate is capped only once several encoders are running:
 * it costs the least of what is on offer, and mirroring six devices is triage,
 * not video review.
 */
export function quality(tiles: number): Quality {
  switch (Math.max(tiles, 1)) {
    case 1:
      return FULL_QUALITY
    case 2:
      return { maxSize: 1024, maxFps: 0 }
    case 3:
    case 4:
      return { maxSize: 800, maxFps: 30 }
    default:
      return { maxSize: 640, maxFps: 24 }
  }
}

/**
 * Columns the auto layout uses for `tiles` tiles in a pane `paneWidth` wide.
 *
 * The preferred shape is picked per count rather than from a square root:
 * phone tiles are portrait, so three across reads better than 2 + 1 for three
 * devices, while four want a 2 × 2. The pane then clamps it — a narrow split
 * drops columns rather than squeezing tiles below `MINIMUM_TILE_WIDTH`.
 */
export function autoColumns(paneWidth: number, tiles: number): number {
  if (tiles <= 1) return 1
  const preferred = preferredColumns(Math.min(tiles, MAXIMUM_DEVICES))
  return Math.min(preferred, Math.max(1, fittingColumns(paneWidth)))
}

function preferredColumns(tiles: number): number {
  switch (tiles) {
    case 2:
      return 2
    case 3:
      return 3
    case 4:
      return 2
    default:
      return 3
  }
}

function fittingColumns(paneWidth: number): number {
  // A pane that has not been measured yet is NaN, and NaN fails every
  // comparison — so the guard is written to let only a real width through.
  if (!Number.isFinite(paneWidth) || paneWidth <= 0) return 1
  return Math.trunc(paneWidth / MINIMUM_TILE_WIDTH)
}

/**
 * Columns for an explicit user choice, clamped to something drawable: at least
 * one, never more than there are tiles.
 *
 * Deliberately *not* clamped by pane width — a manual choice is the user
 * overruling the auto layout, so it stands even when the tiles get small.
 */
export function manualColumns(manual: number, tiles: number): number {
  return Math.min(Math.max(manual, 1), Math.max(tiles, 1))
}

/**
 * Reconcile a stored selection against what is connected: keep the chosen order
 * and drop devices that left.
 *
 * `null` means nobody has picked yet — a wall opened for the first time — which
 * fills with the first `MAXIMUM_DEVICES` connected devices so the feature shows
 * something immediately. An *explicitly emptied* selection stays empty:
 * refilling it would undo the unchecking that emptied it.
 */
export function reconciled(selection: string[] | null, connected: string[]): string[] {
  if (selection === null) return capped(connected)
  const live = new Set(connected)
  return capped(selection.filter((serial) => live.has(serial)))
}

/**
 * Add or remove one device, keeping selection order and the cap.
 *
 * Adding past the cap is refused rather than evicting someone else's tile — the
 * checkbox that would exceed it is disabled, and this is the guard behind that.
 */
export function toggled(serial: string, selection: string[]): string[] {
  const index = selection.indexOf(serial)
  if (index !== -1) return selection.filter((_, at) => at !== index)
  if (selection.length >= MAXIMUM_DEVICES) return selection
  return [...selection, serial]
}

/** Whether one more device can join. */
export function canAdd(selection: string[]): boolean {
  return selection.length < MAXIMUM_DEVICES
}

/**
 * Move a tile, which is what dragging its caption strip does.
 *
 * Returns the selection unchanged for an index that names no tile, so a drop
 * that lands nowhere is a no-op rather than a reordering nobody asked for.
 */
export function moved(selection: string[], from: number, to: number): string[] {
  if (from === to) return selection
  if (from < 0 || from >= selection.length) return selection
  if (to < 0 || to >= selection.length) return selection
  const result = [...selection]
  const [tile] = result.splice(from, 1)
  if (tile === undefined) return selection
  result.splice(to, 0, tile)
  return result
}

function capped(serials: string[]): string[] {
  return serials.slice(0, MAXIMUM_DEVICES)
}
