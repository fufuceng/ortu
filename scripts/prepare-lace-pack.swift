#!/usr/bin/env swift

import AppKit
import CryptoKit
import Foundation

struct PackSpec {
    let input: URL
    let output: URL
    let id: String
    let turkishName: String
    let englishName: String
    let defaultDrop: Double
}

func bitmap(width: Int, height: Int) -> NSBitmapImageRep? {
    NSBitmapImageRep(
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
    )
}

func renderedBitmap(from image: NSImage) throws -> NSBitmapImageRep {
    var proposed = NSRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
        let result = bitmap(width: cgImage.width, height: cgImage.height),
        let context = NSGraphicsContext(bitmapImageRep: result)
    else { throw NSError(domain: "LacePack", code: 1) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    image.draw(
        in: NSRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return result
}

func cleanedLace(from image: NSImage) throws -> NSBitmapImageRep {
    let source = try renderedBitmap(from: image)
    guard let pixels = source.bitmapData else { throw NSError(domain: "LacePack", code: 2) }
    let width = source.pixelsWide
    let height = source.pixelsHigh
    let pixelCount = width * height
    let alphaThreshold: UInt8 = 18

    var labels = [Int32](repeating: 0, count: pixelCount)
    var queue = [Int]()
    queue.reserveCapacity(pixelCount / 3)
    var nextLabel: Int32 = 0
    var largestLabel: Int32 = 0
    var largestCount = 0

    for index in 0 ..< pixelCount where labels[index] == 0 {
        let x = index % width
        let y = index / width
        guard pixels[y * source.bytesPerRow + x * 4 + 3] > alphaThreshold else {
            labels[index] = -1
            continue
        }

        nextLabel += 1
        queue.removeAll(keepingCapacity: true)
        queue.append(index)
        labels[index] = nextLabel
        var head = 0

        while head < queue.count {
            let current = queue[head]
            head += 1
            let currentX = current % width
            let currentY = current / width

            for deltaY in -1 ... 1 {
                for deltaX in -1 ... 1 where deltaX != 0 || deltaY != 0 {
                    let neighborX = currentX + deltaX
                    let neighborY = currentY + deltaY
                    guard neighborX >= 0, neighborX < width,
                        neighborY >= 0, neighborY < height
                    else { continue }
                    let neighbor = neighborY * width + neighborX
                    guard labels[neighbor] == 0 else { continue }
                    let alpha = pixels[neighborY * source.bytesPerRow + neighborX * 4 + 3]
                    if alpha > alphaThreshold {
                        labels[neighbor] = nextLabel
                        queue.append(neighbor)
                    } else {
                        labels[neighbor] = -1
                    }
                }
            }
        }

        if queue.count > largestCount {
            largestCount = queue.count
            largestLabel = nextLabel
        }
    }

    guard largestLabel > 0 else { throw NSError(domain: "LacePack", code: 3) }

    var minimumX = width
    var minimumY = height
    var maximumX = -1
    var maximumY = -1
    for index in 0 ..< pixelCount where labels[index] == largestLabel {
        let x = index % width
        let y = index / width
        minimumX = min(minimumX, x)
        minimumY = min(minimumY, y)
        maximumX = max(maximumX, x)
        maximumY = max(maximumY, y)
    }

    let padding = 2
    minimumX = max(0, minimumX - padding)
    minimumY = max(0, minimumY - padding)
    maximumX = min(width - 1, maximumX + padding)
    maximumY = min(height - 1, maximumY + padding)
    let croppedWidth = maximumX - minimumX + 1
    let croppedHeight = maximumY - minimumY + 1
    guard let output = bitmap(width: croppedWidth, height: croppedHeight),
        let destination = output.bitmapData
    else { throw NSError(domain: "LacePack", code: 4) }

    for outputY in 0 ..< croppedHeight {
        for outputX in 0 ..< croppedWidth {
            let sourceX = minimumX + outputX
            let sourceY = minimumY + outputY
            let sourceIndex = sourceY * width + sourceX
            let sourcePixel = pixels.advanced(by: sourceY * source.bytesPerRow + sourceX * 4)
            let outputPixel = destination.advanced(by: outputY * output.bytesPerRow + outputX * 4)

            guard labels[sourceIndex] == largestLabel else {
                outputPixel[0] = 0
                outputPixel[1] = 0
                outputPixel[2] = 0
                outputPixel[3] = 0
                continue
            }

            let alpha = Double(sourcePixel[3]) / 255
            let red = min(1, Double(sourcePixel[0]) / 255 / max(alpha, 1 / 255))
            let green = min(1, Double(sourcePixel[1]) / 255 / max(alpha, 1 / 255))
            let blue = min(1, Double(sourcePixel[2]) / 255 / max(alpha, 1 / 255))
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let neutralThread = min(1, max(0.20, luminance * 0.92 + 0.08))
            let premultiplied = UInt8((neutralThread * alpha * 255).rounded())
            outputPixel[0] = premultiplied
            outputPixel[1] = premultiplied
            outputPixel[2] = premultiplied
            outputPixel[3] = sourcePixel[3]
        }
    }
    return output
}

func resized(_ source: NSBitmapImageRep, width: Int) throws -> NSBitmapImageRep {
    let height = max(1, Int((Double(source.pixelsHigh) * Double(width) / Double(source.pixelsWide)).rounded()))
    guard let output = bitmap(width: width, height: height),
        let context = NSGraphicsContext(bitmapImageRep: output)
    else { throw NSError(domain: "LacePack", code: 5) }
    let image = NSImage(size: NSSize(width: source.pixelsWide, height: source.pixelsHigh))
    image.addRepresentation(source)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.interpolationQuality = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
    image.draw(
        in: NSRect(x: 0, y: 0, width: width, height: height),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return output
}

func pngData(_ bitmap: NSBitmapImageRep) throws -> Data {
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "LacePack", code: 6)
    }
    return data
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func build(_ spec: PackSpec) throws {
    guard let image = NSImage(contentsOf: spec.input) else { throw NSError(domain: "LacePack", code: 7) }
    let texture2x = try cleanedLace(from: image)
    let texture1x = try resized(texture2x, width: max(1, texture2x.pixelsWide / 2))
    let preview = try resized(texture2x, width: min(720, texture2x.pixelsWide))

    let texture2xData = try pngData(texture2x)
    let texture1xData = try pngData(texture1x)
    let previewData = try pngData(preview)
    let maskData = texture1xData

    try FileManager.default.createDirectory(at: spec.output, withIntermediateDirectories: true)
    let assets: [(String, Data)] = [
        ("texture@1x.png", texture1xData),
        ("texture@2x.png", texture2xData),
        ("mask.png", maskData),
        ("preview.png", previewData),
    ]
    for (name, data) in assets {
        try data.write(to: spec.output.appendingPathComponent(name), options: .atomic)
    }

    let checksums = Dictionary(uniqueKeysWithValues: assets.map { ($0.0, sha256($0.1)) })
    let manifest: [String: Any] = [
        "schemaVersion": 1,
        "id": spec.id,
        "version": "1.0.0",
        "name": ["tr": spec.turkishName, "en": spec.englishName],
        "author": "Örtü Project",
        "license": "CC0-1.0",
        "canvas": ["width": texture2x.pixelsWide, "height": texture2x.pixelsHigh],
        "anchor": "topCenter",
        "defaultDrop": spec.defaultDrop,
        "defaultWidth": 0.98,
        "tintMode": "multiply",
        "assets": [
            "texture1x": "texture@1x.png",
            "texture2x": "texture@2x.png",
            "mask": "mask.png",
            "preview": "preview.png",
        ],
        "sha256": checksums,
    ]
    let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try manifestData.write(to: spec.output.appendingPathComponent("manifest.json"), options: .atomic)
    let license =
        "Original AI-assisted artwork created for the Örtü project.\nDedicated to the public domain under CC0 1.0.\n"
    try Data(license.utf8).write(to: spec.output.appendingPathComponent("LICENSE.txt"), options: .atomic)

    print("\(spec.turkishName): \(texture2x.pixelsWide)x\(texture2x.pixelsHigh), componentPixels=cleaned")
}

guard CommandLine.arguments.count == 7 else {
    fputs("usage: prepare-lace-pack.swift INPUT OUTPUT ID TR_NAME EN_NAME DEFAULT_DROP\n", stderr)
    exit(2)
}

let spec = PackSpec(
    input: URL(fileURLWithPath: CommandLine.arguments[1]),
    output: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true),
    id: CommandLine.arguments[3],
    turkishName: CommandLine.arguments[4],
    englishName: CommandLine.arguments[5],
    defaultDrop: Double(CommandLine.arguments[6]) ?? 0.40
)
try build(spec)
