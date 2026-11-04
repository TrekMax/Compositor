import Foundation

nonisolated enum ModuleCatalog {
    static let depthMini = ModuleDescriptor(
        id: "depth-mini", name: "DepthMini", summary: "Depth estimation for Volumetric Light and depth map extraction", version: "depth-model-1",
        source: URL(string: "https://github.com/robbietilton/Compositor/releases/download/depth-model-1/")!,
        publisher: "Robbie Tilton", homepage: URL(string: "https://github.com/robbietilton/Compositor")!,
        releasePage: URL(string: "https://github.com/robbietilton/Compositor/releases/tag/depth-model-1")!,
        attributions: [
            .init(name: "Depth Anything V2 Small", homepage: URL(string: "https://github.com/DepthAnything/Depth-Anything-V2")!,
                  license: "Apache-2.0", licenseURL: URL(string: "https://github.com/DepthAnything/Depth-Anything-V2/blob/main/LICENSE")!),
            .init(name: "torchvision MobileNetV3 ImageNet weights", homepage: URL(string: "https://github.com/pytorch/vision")!,
                  license: "BSD-3-Clause", licenseURL: URL(string: "https://github.com/pytorch/vision/blob/main/LICENSE")!)
        ],
        assets: [
            .init(name: "Manifest.json", path: "Manifest.json", bytes: 617, sha256: "cfaa07eae081a343ff0e011c2875206d832335e55073252c29c79f73fd938929"),
            .init(name: "model.mlmodel", path: "Data/com.apple.CoreML/model.mlmodel", bytes: 165354, sha256: "c9e2f4f1e44409a2b9f5fb0b072ba41fb42d03a555c333f635f5162676feb744"),
            .init(name: "weight.bin", path: "Data/com.apple.CoreML/weights/weight.bin", bytes: 2491808, sha256: "63d066f1aefc362f2cc0805a624e08df13b6cff3be45dc4307b20a531a2a9f86")
        ], capability: "depth-estimation", packageName: "DepthMini.mlpackage", compiledName: "DepthMini.mlmodelc",
        legacyPath: "Compositor/Depth Model 63d066f1aefc/DepthMini.mlmodelc", inputName: "image", outputName: "depth")
    static let all = [depthMini]
}
