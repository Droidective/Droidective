import AppKit
import CoreImage
import CoreVideo
import Foundation

/// Converts a decoded frame's pixel buffer into shareable image formats for the
/// in-mirror screenshot.
enum MirrorImage {
    /// Pass a shared `context` when converting repeatedly (e.g. a live preview
    /// poll) — a fresh `CIContext` per call is costly. Defaults to a one-shot
    /// context for single conversions like the screenshot.
    static func cgImage(from imageBuffer: CVImageBuffer, context: CIContext = CIContext()) -> CGImage? {
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    static func pngData(from imageBuffer: CVImageBuffer) -> Data? {
        guard let cgImage = cgImage(from: imageBuffer) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    static func nsImage(from imageBuffer: CVImageBuffer, context: CIContext = CIContext()) -> NSImage? {
        guard let cgImage = cgImage(from: imageBuffer, context: context) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
