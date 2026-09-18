import { drawBlurRedactions, drawMarkup } from "@/lib/screenshot-draw"
import type { Annotation, Rect, Size } from "@/lib/screenshot-markup"

/**
 * Turning what is on screen into a file.
 *
 * Every one of these runs the *same* painting code the live canvas runs, at the
 * image's own resolution — which is what makes the markup WYSIWYG, and the
 * reason a second renderer for the export would be a bug waiting to happen.
 */

function makeCanvas(width: number, height: number): HTMLCanvasElement {
  const canvas = document.createElement("canvas")
  canvas.width = Math.max(1, Math.round(width))
  canvas.height = Math.max(1, Math.round(height))
  return canvas
}

function context(canvas: HTMLCanvasElement): CanvasRenderingContext2D {
  const ctx = canvas.getContext("2d")
  if (ctx === null) throw new Error("this browser gave no 2-D canvas context")
  return ctx
}

/** The base image with its markup burned in, at the image's own resolution. */
export function flatten(
  image: CanvasImageSource,
  size: Size,
  annotations: readonly Annotation[],
): HTMLCanvasElement {
  const canvas = makeCanvas(size.width, size.height)
  const ctx = context(canvas)
  ctx.drawImage(image, 0, 0, size.width, size.height)
  drawBlurRedactions(ctx, image, annotations, null, size)
  drawMarkup(ctx, annotations, null, size)
  return canvas
}

/**
 * Crop a flattened image to a normalized rect.
 *
 * A non-zero `rotation` extracts the tilted region *straightened*, by drawing
 * the source turned by −angle about the crop's centre — the Mac's
 * `straightenedCrop`, which is what makes the rotating crop box produce an
 * upright picture rather than one with empty corners.
 */
export function cropped(
  source: CanvasImageSource,
  size: Size,
  rect: Rect,
  rotation: number,
): HTMLCanvasElement {
  const outW = Math.max(1, Math.round(rect.width * size.width))
  const outH = Math.max(1, Math.round(rect.height * size.height))
  const canvas = makeCanvas(outW, outH)
  const ctx = context(canvas)
  ctx.save()
  ctx.translate(outW / 2, outH / 2)
  ctx.rotate(-rotation)
  ctx.translate(
    -(rect.x + rect.width / 2) * size.width,
    -(rect.y + rect.height / 2) * size.height,
  )
  ctx.drawImage(source, 0, 0, size.width, size.height)
  ctx.restore()
  return canvas
}

/** The image turned a quarter-turn, at pixel resolution. */
export function turned(source: CanvasImageSource, size: Size, clockwise: boolean): HTMLCanvasElement {
  const canvas = makeCanvas(size.height, size.width)
  const ctx = context(canvas)
  ctx.translate(canvas.width / 2, canvas.height / 2)
  ctx.rotate(clockwise ? Math.PI / 2 : -Math.PI / 2)
  ctx.drawImage(source, -size.width / 2, -size.height / 2, size.width, size.height)
  return canvas
}

/** PNG bytes for a canvas. */
export async function pngBytes(canvas: HTMLCanvasElement): Promise<Uint8Array> {
  const blob = await new Promise<Blob | null>((resolve) => {
    canvas.toBlob(resolve, "image/png")
  })
  if (blob === null) throw new Error("could not encode the image")
  return new Uint8Array(await blob.arrayBuffer())
}
