import AppKit
import Testing
@testable import Compositor

@MainActor struct PaintBucketTests {
    private func session(width: Int = 6, height: Int = 4, pixels: ((Int, Int) -> [UInt8])? = nil) throws -> EditorSession {
        let session = EditorSession()
        session.createDocument(width: width, height: height)
        if let pixels {
            let context = try BrushRaster.context(width: width, height: height, mask: false)
            let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            for y in 0..<height { for x in 0..<width {
                let value = pixels(x, y)
                for c in 0..<4 { bytes[y * context.bytesPerRow + x * 4 + c] = value[c] }
            } }
            let image = try #require(context.makeImage())
            session.insert(ImportedImage(image: image, thumbnail: image, name: "Pattern"))
        } else { session.addBlankLayer() }
        session.selectTool(.paintBucket)
        session.setPaletteColor(PaletteColor(red: 0, green: 1, blue: 0), background: false)
        return session
    }

    private func pixel(_ session: EditorSession, _ x: Int, _ y: Int) async throws -> [Int] {
        let image = try await ImageExporter.shared.render(#require(session.projectSnapshot())).image
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { Int(bytes[y * context.bytesPerRow + x * 4 + $0]) }
    }

    @Test func contiguousFillStopsAtDifferentColorsAndUndoRedoAreOneStep() async throws {
        let session = try session { x, _ in x == 2 ? [0, 0, 255, 255] : [255, 0, 0, 255] }
        let before = session.history.undoCount
        await session.paintBucket(at: CGPoint(x: 0.5, y: 1.5))
        #expect(session.brushError == nil)
        #expect(try await pixel(session, 0, 1) == [0, 255, 0, 255])
        #expect(try await pixel(session, 2, 1) == [0, 0, 255, 255])
        #expect(try await pixel(session, 4, 1) == [255, 0, 0, 255])
        #expect(session.history.undoCount == before + 1)
        session.undo()
        #expect(try await pixel(session, 0, 1) == [255, 0, 0, 255])
        session.redo()
        #expect(try await pixel(session, 0, 1) == [0, 255, 0, 255])
    }

    @Test func noncontiguousFillReachesSeparatedMatchingRegions() async throws {
        let session = try session { x, _ in x == 2 ? [0, 0, 255, 255] : [255, 0, 0, 255] }
        session.paintBucketSettings.contiguous = false
        await session.paintBucket(at: CGPoint(x: 0.5, y: 1.5))
        #expect(try await pixel(session, 4, 1) == [0, 255, 0, 255])
        #expect(try await pixel(session, 2, 1) == [0, 0, 255, 255])
    }

    @Test func toleranceIncludesTheBoundaryButNotTheNextShade() async throws {
        let session = try session { x, _ in [UInt8(x == 0 ? 100 : x == 1 ? 132 : 133), 0, 0, 255] }
        await session.paintBucket(at: CGPoint(x: 0.5, y: 1.5))
        #expect(try await pixel(session, 1, 1) == [0, 255, 0, 255])
        #expect(try await pixel(session, 2, 1) == [133, 0, 0, 255])
    }

    @Test func transparentCanvasUsesOpacityAndSelectionWithoutChangingTheSelection() async throws {
        let session = try session()
        let selection = DocumentSelection(path: CGPath(rect: CGRect(x: 0, y: 0, width: 2, height: 4), transform: nil), antialiased: false)
        session.setSelection(selection, name: "Test selection")
        session.paintBucketSettings.opacity = 0.5
        await session.paintBucket(at: CGPoint(x: 0.5, y: 1.5))
        let value = try await pixel(session, 0, 1)
        #expect(abs(value[1] - 128) <= 1 && abs(value[3] - 128) <= 1)
        #expect(try await pixel(session, 4, 1) == [0, 0, 0, 0])
        #expect(session.selection == selection)
    }

    @Test func maskFillSamplesMaskAndPreservesImagePixels() async throws {
        let session = try session { _, _ in [255, 0, 0, 255] }
        let original = try #require(session.activeLayer?.asset?.image)
        session.addLayerMask(revealing: true)
        session.selectLayerTarget(try #require(session.activeLayerID), mask: true)
        session.setPaletteColor(.black, background: false)
        await session.paintBucket(at: CGPoint(x: 1, y: 1))
        #expect(session.brushError == nil)
        #expect(try await pixel(session, 1, 1) == [0, 0, 0, 0])
        #expect(session.activeLayer?.asset?.image === original)
        session.undo()
        #expect(try await pixel(session, 1, 1) == [255, 0, 0, 255])
    }

    @Test func invalidClicksAndZeroOpacityLeaveHistoryUntouched() async throws {
        let session = try session()
        let before = session.history.undoCount
        for point in [CGPoint(x: -1, y: 1), CGPoint(x: 6, y: 1), CGPoint(x: CGFloat.nan, y: 1)] {
            await session.paintBucket(at: point)
        }
        session.paintBucketSettings.opacity = 0
        await session.paintBucket(at: CGPoint(x: 1, y: 1))
        #expect(session.history.undoCount == before)
        #expect(session.activeLayer?.asset == nil)
    }
    @Test func scaledLayerKeepsItsNativeResolutionAndPlacement() async throws {
        let session = try session { x, _ in x == 2 || x == 3 ? [0, 0, 255, 255] : [255, 0, 0, 255] }
        let index = try #require(session.document?.layers.firstIndex { $0.id == session.activeLayerID })
        let transform = LayerTransform(origin: CGPoint(x: 1, y: 1), size: CGSize(width: 3, height: 2))
        session.document?.layers[index].transform = transform
        await session.paintBucket(at: CGPoint(x: 1.5, y: 1.5))
        #expect(session.brushError == nil)
        #expect(session.activeLayer?.transform == transform)
        #expect(session.activeLayer?.asset?.image.width == 6)
        #expect(session.activeLayer?.asset?.image.height == 4)
        #expect(try await pixel(session, 1, 1) == [0, 255, 0, 255])
        #expect(try await pixel(session, 3, 1) == [255, 0, 0, 255])
    }

    @Test func clickingOutsideSelectionOrOnHiddenLayerDoesNotEdit() async throws {
        let session = try session()
        session.setSelection(DocumentSelection(path: CGPath(rect: CGRect(x: 0, y: 0, width: 2, height: 4), transform: nil)), name: "Test selection")
        let before = session.history.undoCount
        await session.paintBucket(at: CGPoint(x: 4, y: 1))
        #expect(session.history.undoCount == before)
        session.deselect()
        session.toggleLayerVisibility(try #require(session.activeLayerID))
        let hidden = session.history.undoCount
        await session.paintBucket(at: CGPoint(x: 1, y: 1))
        #expect(session.history.undoCount == hidden)
        #expect(session.activeLayer?.asset == nil)
    }

    @Test func shiftGChoosesBucketAndGStillChoosesGradient() throws {
        let session = try session()
        let canvas = CanvasView(session: session)
        func pressG(_ flags: NSEvent.ModifierFlags) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                characters: "g", charactersIgnoringModifiers: "g", isARepeat: false, keyCode: 5))
            canvas.keyDown(with: event)
        }
        try pressG([])
        #expect(session.tool == .gradient)
        try pressG(.shift)
        #expect(session.tool == .paintBucket)
        session.typeOpacityDigit(5)
        #expect(session.paintBucketSettings.opacity == 0.5)
        #expect(session.gradientSettings.opacity == 1)
    }

    @Test func maskMatchingUsesItsOwnRegionsRatherThanTheLayerColors() async throws {
        let session = try session { _, _ in [255, 0, 0, 255] }
        let context = try BrushRaster.context(width: 6, height: 4, mask: true)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 6, height: 4))
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 2, y: 0, width: 1, height: 4))
        let asset = try LayerMask.asset(from: #require(context.makeImage()))
        let index = try #require(session.document?.layers.firstIndex { $0.id == session.activeLayerID })
        session.document?.layers[index].mask = LayerMask(asset: asset)
        session.selectLayerTarget(try #require(session.activeLayerID), mask: true)
        session.setPaletteColor(.black, background: false)
        await session.paintBucket(at: CGPoint(x: 0.5, y: 1.5))
        #expect(try await pixel(session, 0, 1)[3] == 0)
        #expect(try await pixel(session, 4, 1) == [255, 0, 0, 255])
    }

    @Test func clickingTheTopRegionDoesNotFillTheBottomRegion() async throws {
        let session = try session { _, y in y < 2 ? [255, 0, 0, 255] : [0, 0, 255, 255] }
        await session.paintBucket(at: CGPoint(x: 1.5, y: 0.5))
        #expect(try await pixel(session, 1, 0) == [0, 255, 0, 255])
        #expect(try await pixel(session, 1, 3) == [0, 0, 255, 255])
    }

}
