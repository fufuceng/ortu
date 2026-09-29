import AppKit

enum TransparentImageTrimmer {
    static func trim(_ image: NSImage, alphaThreshold: UInt8 = 2, padding: Int = 2) -> NSImage {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return image
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0,
            let rendered = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            ),
            let context = NSGraphicsContext(bitmapImageRep: rendered),
            let pixels = rendered.bitmapData
        else {
            return image
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        var minimumX = width
        var minimumY = height
        var maximumX = -1
        var maximumY = -1
        let bytesPerRow = rendered.bytesPerRow

        for y in 0 ..< height {
            for x in 0 ..< width where pixels[y * bytesPerRow + x * 4 + 3] > alphaThreshold {
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }

        guard maximumX >= minimumX, maximumY >= minimumY else { return image }

        minimumX = max(0, minimumX - padding)
        minimumY = max(0, minimumY - padding)
        maximumX = min(width - 1, maximumX + padding)
        maximumY = min(height - 1, maximumY + padding)

        let croppedWidth = maximumX - minimumX + 1
        let croppedHeight = maximumY - minimumY + 1
        guard croppedWidth < width || croppedHeight < height,
            let cropped = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: croppedWidth,
                pixelsHigh: croppedHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: croppedWidth * 4,
                bitsPerPixel: 32
            ),
            let destination = cropped.bitmapData
        else {
            return image
        }

        let rowByteCount = croppedWidth * 4
        for row in 0 ..< croppedHeight {
            destination.advanced(by: row * cropped.bytesPerRow).update(
                from: pixels.advanced(by: (minimumY + row) * bytesPerRow + minimumX * 4),
                count: rowByteCount
            )
        }

        let result = NSImage(size: NSSize(width: croppedWidth, height: croppedHeight))
        result.addRepresentation(cropped)
        return result
    }
}
