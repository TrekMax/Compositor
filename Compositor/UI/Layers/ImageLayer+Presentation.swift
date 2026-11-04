import CoreGraphics
import Foundation

extension ImageLayer {
    /// The layer's size on the canvas and, once it's scaled, by how much, for its row. A photo shrunk to 5% keeps
    /// every one of its pixels; the percentage says so, where the size alone reads as if it had been resampled small.
    var sizeLabel: String {
        let text = L10n.format("%ld × %ld px", Int(size.width.rounded()), Int(size.height.rounded()))
        guard let pixels = asset?.image.width, pixels > 0 else { return text }
        // Measured across the width, as the Transform bar's Scale field is.
        let percent = Double(size.width) / Double(pixels) * 100
        guard abs(percent - 100) >= 0.05 else { return text }
        return L10n.format("%@ · %@%%", text, percent.formatted(.number.precision(.fractionLength(0...1)).locale(LanguageSettings.shared.locale)))
    }

    /// The tag after the size of an animated GIF layer, or of a layer keeping 16 bits a channel or light brighter than
    /// white (`DeepLayer`), which goes once it's rasterized to 8.
    var depthLabel: String? {
        if gifAnimation != nil { return "GIF" }
        guard let asset, asset.deep != nil, liveText == nil, adjustment == nil, !isGroup else { return nil }
        return asset.isHDR ? "HDR" : "16-Bit"
    }
}
