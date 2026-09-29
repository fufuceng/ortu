import AppKit

@MainActor
final class OverlayView: NSView {
    private static var imageCache: [String: NSImage] = [:]
    private static let imageCacheLimit = 8

    private var coverAppearance: OverlayAppearance
    private let onRequestFold: () -> Void
    private var interaction = OverlayInteractionState()
    private var coverImage: NSImage?
    private var settleTask: Task<Void, Never>?
    private var entranceTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?

    init(frame: NSRect, appearance: OverlayAppearance, onRequestFold: @escaping () -> Void) {
        coverAppearance = appearance
        coverImage = Self.loadImage(for: appearance)
        self.onRequestFold = onRequestFold
        super.init(frame: frame)
        wantsLayer = true
        layer?.drawsAsynchronously = true
        setAccessibilityLabel("Örtü masaüstü katmanı")
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    func update(appearance: OverlayAppearance) {
        if appearance.textureURL != coverAppearance.textureURL || appearance.tintColor != coverAppearance.tintColor {
            coverImage = Self.loadImage(for: appearance)
        }
        coverAppearance = appearance
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func resetInteraction() {
        settleTask?.cancel()
        settleTask = nil
        entranceTask?.cancel()
        entranceTask = nil
        dismissalTask?.cancel()
        dismissalTask = nil
        interaction.reset()
        startEntranceAnimation()
    }

    func dismiss(animated: Bool, completion: @escaping @MainActor () -> Void) {
        settleTask?.cancel()
        settleTask = nil
        entranceTask?.cancel()
        entranceTask = nil
        dismissalTask?.cancel()

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            interaction.finishDismissal()
            needsDisplay = true
            completion()
            return
        }

        let initialFoldProgress = interaction.foldProgress
        let initialBackgroundVisibility = interaction.backgroundVisibility
        let initialCoverVisibility = interaction.coverVisibility
        dismissalTask = Task { @MainActor in
            let frameCount = 22
            for frame in 1 ... frameCount {
                guard !Task.isCancelled else { return }
                interaction.applyDismissal(
                    progress: Double(frame) / Double(frameCount),
                    initialFoldProgress: initialFoldProgress,
                    initialBackgroundVisibility: initialBackgroundVisibility,
                    initialCoverVisibility: initialCoverVisibility
                )
                needsDisplay = true
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            guard !Task.isCancelled else { return }
            interaction.finishDismissal()
            needsDisplay = true
            dismissalTask = nil
            completion()
        }
    }

    override func resetCursorRects() {
        addCursorRect(coverRect, cursor: .openHand)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onRequestFold()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        settleTask?.cancel()
        settleTask = nil
        entranceTask?.cancel()
        entranceTask = nil
        let point = convert(event.locationInWindow, from: nil)
        guard interaction.beginDrag(at: point, coverRect: coverRect) else { return }
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        interaction.updateDrag(to: point, threshold: max(120, bounds.height * 0.28))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.openHand.set()
        if interaction.endDrag() == .dismiss {
            onRequestFold()
        } else {
            settleToRest()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()

        if coverAppearance.dimAmount > 0 {
            NSColor.black.withAlphaComponent(
                coverAppearance.dimAmount * interaction.backgroundVisibility
            ).setFill()
            bounds.fill()
        }

        let destination = coverRect
        guard destination.height > 3, destination.width > 3 else {
            context.restoreGState()
            return
        }

        if let coverImage {
            if interaction.dragOffset == .zero {
                context.setShadow(
                    offset: CGSize(width: 0, height: -6),
                    blur: 14,
                    color: NSColor.black.withAlphaComponent(0.38 * interaction.coverVisibility).cgColor
                )
                coverImage.draw(
                    in: destination,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: coverAppearance.opacity * interaction.coverVisibility,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
            } else {
                drawDeformed(image: coverImage, in: destination, context: context)
            }
            context.restoreGState()
            return
        }

        let left = destination.minX
        let right = destination.maxX
        let top = destination.maxY
        let bottom = destination.minY

        let coverPath = NSBezierPath()
        coverPath.move(to: NSPoint(x: left, y: top))
        coverPath.line(to: NSPoint(x: right, y: top))
        coverPath.line(to: NSPoint(x: bounds.midX, y: bottom))
        coverPath.close()

        NSGraphicsContext.saveGraphicsState()
        coverPath.addClip()
        NSColor(
            calibratedRed: 0.93,
            green: 0.90,
            blue: 0.82,
            alpha: coverAppearance.opacity * interaction.coverVisibility
        ).setFill()
        bounds.fill()

        let spacing: CGFloat = 34
        NSColor(
            calibratedWhite: 0.35,
            alpha: 0.18 * coverAppearance.opacity * interaction.coverVisibility
        ).setStroke()
        for offset in stride(from: -bounds.height, through: bounds.width + bounds.height, by: spacing) {
            let forward = NSBezierPath()
            forward.move(to: NSPoint(x: offset, y: bounds.minY))
            forward.line(to: NSPoint(x: offset + bounds.height, y: bounds.maxY))
            forward.lineWidth = 1
            forward.stroke()

            let backward = NSBezierPath()
            backward.move(to: NSPoint(x: offset, y: bounds.maxY))
            backward.line(to: NSPoint(x: offset + bounds.height, y: bounds.minY))
            backward.lineWidth = 1
            backward.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        NSColor(
            calibratedWhite: 0.25,
            alpha: 0.24 * coverAppearance.opacity * interaction.coverVisibility
        ).setStroke()
        coverPath.lineWidth = 1
        coverPath.stroke()

        context.restoreGState()
    }

    private var coverRect: NSRect {
        OverlayLayout.coverRect(
            in: bounds,
            imageSize: coverImage?.size,
            width: coverAppearance.width,
            drop: coverAppearance.drop,
            foldProgress: interaction.foldProgress
        )
    }

    private func drawDeformed(image: NSImage, in rect: NSRect, context: CGContext) {
        guard let grabPoint = interaction.grabPoint else { return }

        let columns = 10
        let rows = 7
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let x0 = rect.minX + rect.width * CGFloat(column) / CGFloat(columns)
                let x1 = rect.minX + rect.width * CGFloat(column + 1) / CGFloat(columns)
                let y0 = rect.minY + rect.height * CGFloat(row) / CGFloat(rows)
                let y1 = rect.minY + rect.height * CGFloat(row + 1) / CGFloat(rows)

                let bottomLeft = CGPoint(x: x0, y: y0)
                let bottomRight = CGPoint(x: x1, y: y0)
                let topLeft = CGPoint(x: x0, y: y1)
                let topRight = CGPoint(x: x1, y: y1)

                draw(
                    image: image,
                    source: .init(first: bottomLeft, second: bottomRight, third: topRight),
                    destination: .init(
                        first: displaced(bottomLeft, in: rect, grabPoint: grabPoint),
                        second: displaced(bottomRight, in: rect, grabPoint: grabPoint),
                        third: displaced(topRight, in: rect, grabPoint: grabPoint)
                    ),
                    imageRect: rect,
                    context: context
                )
                draw(
                    image: image,
                    source: .init(first: bottomLeft, second: topRight, third: topLeft),
                    destination: .init(
                        first: displaced(bottomLeft, in: rect, grabPoint: grabPoint),
                        second: displaced(topRight, in: rect, grabPoint: grabPoint),
                        third: displaced(topLeft, in: rect, grabPoint: grabPoint)
                    ),
                    imageRect: rect,
                    context: context
                )
            }
        }
    }

    private func displaced(_ point: CGPoint, in rect: CGRect, grabPoint: CGPoint) -> CGPoint {
        ClothMesh.displacedPoint(point, in: rect, grabPoint: grabPoint, dragOffset: interaction.dragOffset)
    }

    private func draw(
        image: NSImage,
        source: ClothMesh.Triangle,
        destination: ClothMesh.Triangle,
        imageRect: CGRect,
        context: CGContext
    ) {
        guard let transform = ClothMesh.affineTransform(from: source, to: destination) else { return }

        context.saveGState()
        let clip = CGMutablePath()
        clip.move(to: destination.first)
        clip.addLine(to: destination.second)
        clip.addLine(to: destination.third)
        clip.closeSubpath()
        context.addPath(clip)
        context.clip()
        context.concatenate(transform)
        image.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: coverAppearance.opacity * interaction.coverVisibility,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.restoreGState()
    }

    private func settleToRest() {
        guard interaction.dragOffset != .zero || interaction.foldProgress != 0 else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            interaction.finishTransition()
            needsDisplay = true
            return
        }

        let initialOffset = interaction.dragOffset
        let initialFoldProgress = interaction.foldProgress
        let initialBackgroundVisibility = interaction.backgroundVisibility
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let frameCount = 24
            for frame in 1 ... frameCount {
                guard !Task.isCancelled else { return }
                self.interaction.applySettlement(
                    progress: Double(frame) / Double(frameCount),
                    initialOffset: initialOffset,
                    initialFoldProgress: initialFoldProgress,
                    initialBackgroundVisibility: initialBackgroundVisibility
                )
                self.needsDisplay = true
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            guard !Task.isCancelled else { return }
            self.interaction.finishTransition()
            self.settleTask = nil
            self.needsDisplay = true
        }
    }

    private func startEntranceAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            interaction.finishTransition()
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }

        interaction.applyEntrance(progress: 0)
        needsDisplay = true
        entranceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let frameCount = 18
            for frame in 1 ... frameCount {
                guard !Task.isCancelled else { return }
                self.interaction.applyEntrance(progress: Double(frame) / Double(frameCount))
                self.needsDisplay = true
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            guard !Task.isCancelled else { return }
            self.interaction.finishTransition()
            self.entranceTask = nil
            self.needsDisplay = true
            self.window?.invalidateCursorRects(for: self)
        }
    }

    private static func loadImage(for appearance: OverlayAppearance) -> NSImage? {
        guard let textureURL = appearance.textureURL else { return nil }
        let cacheKey = textureURL.path + "|" + (appearance.tintColor?.hexRGB ?? "original")
        if let cached = imageCache[cacheKey] { return cached }

        guard let loaded = NSImage(contentsOf: textureURL) else { return nil }
        let source = TransparentImageTrimmer.trim(loaded)
        let result = appearance.tintColor.map { ThreadTintRenderer.tint(source, color: $0) } ?? source

        if imageCache.count >= imageCacheLimit, let oldestKey = imageCache.keys.first {
            imageCache[oldestKey] = nil
        }
        imageCache[cacheKey] = result
        return result
    }
}
