import AppKit

nonisolated struct PaintBucketSettings: Equatable, Sendable {
    var tolerance = 32
    var opacity: CGFloat = 1
    var contiguous = true
}

private nonisolated struct PaintBucketJob: @unchecked Sendable {
    let image: CGImage
    let point: CGPoint
    let settings: WandSettings
}

private nonisolated struct PaintBucketRegion: @unchecked Sendable {
    let path: CGPath?
}

extension EditorSession {
    /// Match the clicked target's colors without changing the document selection, then fill through
    /// that selection in the layer's own pixel grid. Matching runs off the main thread.
    func paintBucket(at point: CGPoint) async {
        guard tool == .paintBucket, !isProjectBusy else { return }
        guard canPaint, let document, let layer = activeLayer else { brushError = paintRefusal; return }
        guard point.x.isFinite, point.y.isFinite,
              CGRect(origin: .zero, size: document.size).contains(point),
              selection.map({ $0.path.contains(point) }) != false,
              paintBucketSettings.opacity.isFinite, paintBucketSettings.opacity > 0 else { return }
        let opacity = min(1, paintBucketSettings.opacity)
        let mask = isMaskSelected
        let value = paletteColor(background: false)
        let color = mask ? CGColor(gray: value.red, alpha: 1)
            : CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                      components: [value.red, value.green, value.blue, 1])!
        finishOpacityEdit()
        isProjectBusy = true
        defer { isProjectBusy = false }
        do {
            let edit = try makeRasterEdit(for: layer, growsMask: true)
            let sample = try BrushRaster.context(width: document.width, height: document.height, mask: false)
            if mask, let layerMask = layer.mask {
                // A placed mask keeps its own transform and its background outside its image.
                sample.setFillColor(gray: LayerMask.background(of: layerMask.asset.thumbnail), alpha: 1)
                sample.fill(CGRect(origin: .zero, size: document.size))
                LayerRenderer.draw(layerMask.asset.image, transform: layer.maskTransform,
                                   center: layer.maskTransform.center, in: sample)
            } else if let image = layer.asset?.image {
                LayerRenderer.draw(image, transform: layer.transform, center: layer.transform.center, in: sample)
            }
            guard let image = sample.makeImage() else { throw ExportError.render }
            var settings = WandSettings()
            settings.tolerance = min(255, max(0, paintBucketSettings.tolerance))
            settings.contiguous = paintBucketSettings.contiguous
            let job = PaintBucketJob(image: image, point: point, settings: settings)
            let region = try await Task.detached(priority: .userInitiated) {
                PaintBucketRegion(path: try MagicWand.select(in: job.image, at: job.point, settings: job.settings))
            }.value
            guard self.document?.id == document.id, let path = region.path else { return }
            try edit.fill(color, in: path, opacity: opacity)
            guard !edit.patches.isEmpty else { return }
            try await commitRasterEdit(edit, name: "Paint Bucket")
            brushRevision += 1
        } catch { brushError = error.localizedDescription }
    }
}
