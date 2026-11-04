import CoreGraphics
import CoreML
import Foundation
import Vision

nonisolated protocol DepthPredicting: Sendable {
    func depth(for image: CGImage) -> DepthMap?
}

/// Core ML's pixel adapter. Flexible input shapes do not declare fixed output dimensions.
nonisolated final class CoreMLDepthPredictor: DepthPredicting, @unchecked Sendable {
    private let model: MLModel
    init(at url: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: configuration)
        guard model.modelDescription.inputDescriptionsByName["image"]?.type == .image,
              model.modelDescription.outputDescriptionsByName["depth"]?.type == .multiArray else {
            throw ModuleState.Issue(code: .runtime, message: "The depth model has an incompatible interface.")
        }
    }
    func depth(for image: CGImage) -> DepthMap? {
        // Scaled to the nearest of the model's shapes at 8 bits first: Core ML takes a 16-bit or HDR layer's pixels no
        // other way.
        let (columns, rows) = DepthModel.shape(for: image)
        guard let small = pixels(of: image, width: columns, height: rows),
              let input = try? MLFeatureValue(cgImage: small.image, pixelsWide: columns, pixelsHigh: rows, pixelFormatType: kCVPixelFormatType_32BGRA,
                                              options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue]),
              let output = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": input])),
              let array = output.featureValue(for: "depth")?.multiArrayValue, array.count == columns * rows else { return nil }
        let values = MLShapedArray<Float>(converting: array).scalars
        guard let low = values.min(), let high = values.max(), high > low else { return nil }
        // Enlarged to the photo's shape, then onto its edges, its brightness the guide.
        let scale = Double(DepthModel.refinedSide) / Double(max(image.width, image.height))
        let width = max(8, Int((Double(image.width) * scale).rounded())), height = max(8, Int((Double(image.height) * scale).rounded()))
        guard let guide = pixels(of: image, width: width, height: height) else { return nil }
        var enlarged = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let fy = min(Float(rows - 1), max(0, (Float(y) + 0.5) * Float(rows) / Float(height) - 0.5))
            let y0 = Int(fy), y1 = min(rows - 1, y0 + 1), ty = fy - Float(y0)
            for x in 0..<width {
                let fx = min(Float(columns - 1), max(0, (Float(x) + 0.5) * Float(columns) / Float(width) - 0.5))
                let x0 = Int(fx), x1 = min(columns - 1, x0 + 1), tx = fx - Float(x0)
                let top = values[y0 * columns + x0] * (1 - tx) + values[y0 * columns + x1] * tx
                let bottom = values[y1 * columns + x0] * (1 - tx) + values[y1 * columns + x1] * tx
                enlarged[y * width + x] = ((top * (1 - ty) + bottom * ty) - low) / (high - low)
            }
        }
        let refined = GuidedMatte.filter(mask: enlarged, guide: guide.gray, width: width, height: height,
                                         radius: max(2, DepthModel.refinedSide / 48), epsilon: 1e-3).map { max(0, min(1, $0)) }
        let depth = DepthMap(values: refined, width: width, height: height)
        return depth
    }

    /// `image` at `width` × `height`, 8 bits, and its brightness 0–1, rows top-down.
    private func pixels(of image: CGImage, width: Int, height: Int) -> (image: CGImage, gray: [Float])? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let made = context.makeImage(), let data = context.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var gray = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let p = bytes + y * context.bytesPerRow + x * 4
                gray[y * width + x] = (0.2126 * Float(p[0]) + 0.7152 * Float(p[1]) + 0.0722 * Float(p[2])) / 255
            }
        }
        return (made, gray)
    }

}
