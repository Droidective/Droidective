import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The QR code for a pairing payload, drawn on its own white card.
///
/// Deliberately theme-blind — the one view in the app that ignores the
/// `.bgSurface` / translucency tokens. A scanner needs dark modules on a light
/// ground and a quiet zone around the symbol, so a QR tinted to match a dark
/// translucent window is a QR that doesn't scan. The white card is the feature
/// working, not a missed token.
struct QrCodeImage: View {
    let payload: String
    var side: CGFloat = 190

    @State private var rendered: CGImage?

    var body: some View {
        Group {
            if let rendered {
                Image(decorative: rendered, scale: 1)
                    // Nearest-neighbour: a QR upscaled with smoothing has soft
                    // module edges, which is what makes a scan take three tries.
                    .interpolation(.none)
                    .resizable()
                    .frame(width: side, height: side)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: side, height: side)
            }
        }
        // The quiet zone. Without it a scanner can't find the symbol's edges.
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .task(id: payload) { rendered = Self.render(payload) }
        .accessibilityLabel("Pairing QR code")
    }

    /// The QR bitmap for `payload`, at whole-module resolution.
    ///
    /// `CIQRCodeGenerator` emits one pixel per module, so the image is scaled
    /// by an integer factor before it leaves Core Image — a fractional scale
    /// lands module boundaries mid-pixel and no amount of nearest-neighbour
    /// display fixes that.
    static func render(_ payload: String, modulePixels: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(
            by: CGAffineTransform(scaleX: modulePixels, y: modulePixels))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
