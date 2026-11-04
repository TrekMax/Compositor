import CoreGraphics
import CoreImage
import Foundation

/// DepthMini's optional depth capability, installed and enabled by the module manager.
nonisolated enum DepthModel {
    static let runtime = DepthRuntime()
    static var isReady: Bool { runtime.isReady }
    static var revision: UInt64 { runtime.revision }
    @discardableResult static func prepare() async -> Bool {
        await ModuleManager.shared.prepare(ModuleCatalog.depthMini.id)
    }
    static func depth(for image: CGImage) -> DepthMap? { runtime.depth(for: image) }
    static let refinedSide = 640
    /// The sizes the model takes, width × height: square, 4:3 and 16:9 either way up.
    static let shapes = [(512, 512), (512, 384), (512, 288), (384, 512), (288, 512)]

    /// The shape nearest `image`'s proportions, so it's scaled to fit rather than squashed square.
    static func shape(for image: CGImage) -> (width: Int, height: Int) {
        let aspect = log(Double(image.width) / Double(max(1, image.height)))
        return shapes.min { abs(log(Double($0.0) / Double($0.1)) - aspect) < abs(log(Double($1.0) / Double($1.1)) - aspect) }!
    }

    /// `depth` as an image over `extent` (Core Image's coordinates), smoothly enlarged: 16-bit gray, read as it is
    /// (Core Image makes nothing of float pixels handed to it directly).
    static func image(_ depth: DepthMap, over extent: CGRect) -> CIImage {
        let levels = depth.values.map { UInt16(max(0, min(1, $0)) * 65535) }
        guard let provider = CGDataProvider(data: levels.withUnsafeBytes { Data($0) } as CFData),
              let gray = CGImage(width: depth.width, height: depth.height, bitsPerComponent: 16, bitsPerPixel: 16, bytesPerRow: depth.width * 2,
                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder16Little.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return CIImage.black.cropped(to: extent)
        }
        return CIImage(cgImage: gray, options: [.colorSpace: NSNull()]).samplingLinear()
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)
                .scaledBy(x: extent.width / CGFloat(depth.width), y: extent.height / CGFloat(depth.height)))
            .cropped(to: extent)
    }
}
