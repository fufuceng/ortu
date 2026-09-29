import AppKit

enum ThreadTintRenderer {
    static func tint(_ image: NSImage, color: RGBAColor) -> NSImage {
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

        for y in 0 ..< height {
            let row = pixels.advanced(by: y * rendered.bytesPerRow)
            for x in 0 ..< width {
                let pixel = row.advanced(by: x * 4)
                let alpha = Double(pixel[3]) / 255
                guard alpha > 0 else { continue }

                let red = min(1, Double(pixel[0]) / 255 / alpha)
                let green = min(1, Double(pixel[1]) / 255 / alpha)
                let blue = min(1, Double(pixel[2]) / 255 / alpha)
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

                pixel[0] = channel(color.red, luminance: luminance, alpha: alpha)
                pixel[1] = channel(color.green, luminance: luminance, alpha: alpha)
                pixel[2] = channel(color.blue, luminance: luminance, alpha: alpha)
            }
        }

        let result = NSImage(size: image.size)
        result.addRepresentation(rendered)
        return result
    }

    static func shadedComponent(_ component: Double, luminance: Double) -> Double {
        let threadDepth = 0.58 + OverlayLayout.clamp(luminance, to: 0 ... 1) * 0.48
        let highlight = pow(OverlayLayout.clamp(luminance, to: 0 ... 1), 3) * 0.10
        return OverlayLayout.clamp(component * threadDepth + highlight, to: 0 ... 1)
    }

    private static func channel(_ component: Double, luminance: Double, alpha: Double) -> UInt8 {
        UInt8((shadedComponent(component, luminance: luminance) * alpha * 255).rounded())
    }
}
