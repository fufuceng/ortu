import AppKit
import Testing
import CoreGraphics
@testable import Ortu

@Suite("Overlay layout")
struct OverlayLayoutTests {
    @Test("Clamp keeps values inside the supported range")
    func clamp() {
        #expect(OverlayLayout.clamp(0.1, to: 0.2 ... 0.8) == 0.2)
        #expect(OverlayLayout.clamp(0.5, to: 0.2 ... 0.8) == 0.5)
        #expect(OverlayLayout.clamp(0.9, to: 0.2 ... 0.8) == 0.8)
    }

    @Test("Fold progress is normalized")
    func foldProgress() {
        #expect(OverlayLayout.foldProgress(dragDistance: -20, threshold: 100) == 0)
        #expect(OverlayLayout.foldProgress(dragDistance: 40, threshold: 100) == 0.4)
        #expect(OverlayLayout.foldProgress(dragDistance: 200, threshold: 100) == 1)
        #expect(OverlayLayout.foldProgress(dragDistance: 10, threshold: 0) == 1)
    }

    @Test("Dismissal folds the cover while fading the background")
    func dismissalState() {
        let start = OverlayLayout.dismissalState(progress: 0)
        let middle = OverlayLayout.dismissalState(progress: 0.5)
        let end = OverlayLayout.dismissalState(progress: 1)

        #expect(
            start
                == OverlayDismissalState(
                    foldProgress: 0,
                    backgroundVisibility: 1,
                    coverVisibility: 1
                ))
        #expect(middle.foldProgress > start.foldProgress)
        #expect(middle.backgroundVisibility < start.backgroundVisibility)
        #expect(middle.coverVisibility < start.coverVisibility)
        #expect(
            end
                == OverlayDismissalState(
                    foldProgress: 1,
                    backgroundVisibility: 0,
                    coverVisibility: 0
                ))
    }

    @Test("Background reveals continuously while the cover is pulled")
    func interactiveBackgroundFade() {
        let resting = OverlayLayout.backgroundVisibility(foldProgress: 0)
        let halfway = OverlayLayout.backgroundVisibility(foldProgress: 0.5)
        let removed = OverlayLayout.backgroundVisibility(foldProgress: 1)

        #expect(resting == 1)
        #expect(halfway == 0.5)
        #expect(removed == 0)
    }

    @Test("A wide motif keeps its natural height while filling the display")
    func widthPrimaryNaturalHeight() {
        let bounds = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let rect = OverlayLayout.coverRect(
            in: bounds,
            imageSize: CGSize(width: 2_000, height: 500),
            width: 0.9,
            drop: 0.5,
            foldProgress: 0
        )

        #expect(rect == CGRect(x: 96, y: 648, width: 1_728, height: 432))
    }

    @Test("A narrow drop does not reduce cover width")
    func narrowDropKeepsWidth() {
        let rect = OverlayLayout.coverRect(
            in: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            imageSize: CGSize(width: 1_000, height: 1_000),
            width: 0.9,
            drop: 0.2,
            foldProgress: 0
        )

        #expect(rect == CGRect(x: 96, y: 864, width: 1_728, height: 216))
    }

    @Test("Transparent padding is removed from motif assets")
    @MainActor
    func transparentImageTrim() throws {
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 100,
                pixelsHigh: 80,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: 400,
                bitsPerPixel: 32
            ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: representation))
        context.cgContext.clear(CGRect(x: 0, y: 0, width: 100, height: 80))
        context.cgContext.setFillColor(NSColor.white.cgColor)
        context.cgContext.fill(CGRect(x: 20, y: 25, width: 40, height: 20))

        let image = NSImage(size: NSSize(width: 100, height: 80))
        image.addRepresentation(representation)

        let trimmed = TransparentImageTrimmer.trim(image, padding: 0)

        #expect(trimmed.size == NSSize(width: 40, height: 20))
    }

    @Test("Dynamic tint preserves thread highlights and shadows")
    func texturedTint() {
        let shadow = ThreadTintRenderer.shadedComponent(0.7, luminance: 0.15)
        let midtone = ThreadTintRenderer.shadedComponent(0.7, luminance: 0.5)
        let highlight = ThreadTintRenderer.shadedComponent(0.7, luminance: 0.9)

        #expect(shadow < midtone)
        #expect(midtone < highlight)
        #expect(highlight <= 1)
    }

    @Test("Cloth deformation pins the top seam and follows the grab point")
    func clothDeformation() {
        let rect = CGRect(x: 0, y: 0, width: 1_000, height: 500)
        let grab = CGPoint(x: 500, y: 100)
        let offset = CGSize(width: 120, height: 80)

        let pinned = ClothMesh.displacedPoint(
            CGPoint(x: 500, y: rect.maxY),
            in: rect,
            grabPoint: grab,
            dragOffset: offset
        )
        let followed = ClothMesh.displacedPoint(grab, in: rect, grabPoint: grab, dragOffset: offset)

        #expect(pinned == CGPoint(x: 500, y: 500))
        #expect(followed.x > grab.x + 90)
        #expect(followed.y > grab.y + 60)
    }

    @Test("Triangle transform maps all source corners")
    func triangleTransform() throws {
        let source = ClothMesh.Triangle(
            first: CGPoint(x: 0, y: 0),
            second: CGPoint(x: 2, y: 0),
            third: CGPoint(x: 0, y: 2)
        )
        let destination = ClothMesh.Triangle(
            first: CGPoint(x: 10, y: 20),
            second: CGPoint(x: 14, y: 20),
            third: CGPoint(x: 10, y: 26)
        )
        let transform = try #require(ClothMesh.affineTransform(from: source, to: destination))

        #expect(source.first.applying(transform) == destination.first)
        #expect(source.second.applying(transform) == destination.second)
        #expect(source.third.applying(transform) == destination.third)
    }

    @Test("Tint colors round-trip through persisted hex")
    func tintColorHex() throws {
        let color = try #require(RGBAColor(hexRGB: "#D06655"))

        #expect(color.hexRGB == "#D06655")
        #expect(RGBAColor(hexRGB: "invalid") == nil)
    }

    @Test("Interaction state rejects misses and tracks a continuous drag")
    func interactionDrag() {
        var state = OverlayInteractionState()
        let cover = CGRect(x: 100, y: 400, width: 800, height: 300)

        let missed = state.beginDrag(at: CGPoint(x: 10, y: 10), coverRect: cover)
        let grabbed = state.beginDrag(at: CGPoint(x: 500, y: 450), coverRect: cover)
        #expect(!missed)
        #expect(grabbed)
        state.updateDrag(to: CGPoint(x: 620, y: 550), threshold: 200)

        #expect(state.dragOffset == CGSize(width: 120, height: 100))
        #expect(state.foldProgress == 0.5)
        #expect(state.backgroundVisibility == 0.5)
        #expect(state.endDrag() == .dismiss)
    }

    @Test("Interaction transitions have deterministic endpoints")
    func interactionTransitions() {
        var state = OverlayInteractionState()

        state.applyEntrance(progress: 0)
        #expect(state.foldProgress == 1)
        #expect(state.backgroundVisibility == 0)
        state.applyEntrance(progress: 1)
        #expect(state.foldProgress == 0)
        #expect(state.backgroundVisibility == 1)

        state.applyDismissal(
            progress: 1,
            initialFoldProgress: 0.2,
            initialBackgroundVisibility: 0.8,
            initialCoverVisibility: 0.7
        )
        #expect(state.foldProgress == 1)
        #expect(state.backgroundVisibility == 0)
        #expect(state.coverVisibility == 0)

        state.finishTransition()
        #expect(state == OverlayInteractionState())
    }

    @Test("Settlement returns deformation and dimming to rest")
    func interactionSettlement() {
        var state = OverlayInteractionState()

        state.applySettlement(
            progress: 1,
            initialOffset: CGSize(width: 100, height: 80),
            initialFoldProgress: 0.6,
            initialBackgroundVisibility: 0.4
        )

        #expect(abs(state.dragOffset.width) < 1)
        #expect(abs(state.dragOffset.height) < 1)
        #expect(state.foldProgress == 0)
        #expect(state.backgroundVisibility == 1)
    }
}
