/**
 * The two DOM details every drag-to-reorder surface needs.
 *
 * View helpers rather than logic — what a drop *does* to an order lives in
 * `lib/ordering.ts`, where it is tested. These only read the pointer.
 */

/**
 * Start a drag.
 *
 * WebKit — the webview on Linux and macOS — starts no drag at all unless the
 * event carries data, so this is not decoration. The payload is unused: what is
 * being dragged is React state, which survives the round trip and cannot be
 * forged by a drop from outside the window.
 */
export function startDrag(event: React.DragEvent<HTMLElement>): void {
  event.dataTransfer.effectAllowed = "move"
  event.dataTransfer.setData("text/plain", "")
}

/** Whether the pointer is below the halfway line of the row it is over. */
export function pastMidpointY(event: React.DragEvent<HTMLElement>): boolean {
  const box = event.currentTarget.getBoundingClientRect()
  return event.clientY > box.top + box.height / 2
}

/** Whether the pointer is right of the halfway line of the chip it is over. */
export function pastMidpointX(event: React.DragEvent<HTMLElement>): boolean {
  const box = event.currentTarget.getBoundingClientRect()
  return event.clientX > box.left + box.width / 2
}

/**
 * Whether a drag is carrying files from outside the window.
 *
 * `types` rather than `files`, because during a drag the file list is empty for
 * security and this is the only signal. In-app reorder targets check it so an
 * APK dragged in from the file manager is not also read as a reorder: an empty
 * `text/plain` reads back as `Number("") === 0`, a perfectly valid index.
 */
export function carriesFiles(event: React.DragEvent<HTMLElement>): boolean {
  return event.dataTransfer.types.includes("Files")
}
