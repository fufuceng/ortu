import CryptoKit
import Foundation
import ImageIO

struct CoverPackManifest: Codable, Equatable, Sendable {
    struct Canvas: Codable, Equatable, Sendable {
        let width: Int
        let height: Int
    }

    struct Assets: Codable, Equatable, Sendable {
        let texture1x: String
        let texture2x: String
        let mask: String
        let preview: String?

        var allFilenames: [String] {
            [texture1x, texture2x, mask, preview].compactMap { $0 }
        }
    }

    let schemaVersion: Int
    let id: String
    let version: String
    let name: [String: String]
    let author: String
    let license: String
    let canvas: Canvas
    let anchor: String
    let defaultDrop: Double
    let defaultWidth: Double
    let tintMode: String
    let assets: Assets
    let sha256: [String: String]?
}

struct ValidatedCoverPack: Equatable, Sendable {
    let url: URL
    let manifest: CoverPackManifest
    let totalBytes: Int64
}

enum CoverPackError: LocalizedError, Equatable {
    case notPackage
    case symbolicLink
    case missingManifest
    case manifestTooLarge
    case malformedManifest
    case unsupportedSchema(Int)
    case invalidIdentifier
    case invalidVersion
    case invalidMetadata(String)
    case invalidAssetPath(String)
    case missingAsset(String)
    case unsupportedAsset(String)
    case unexpectedEntry(String)
    case tooManyFiles
    case packageTooLarge
    case archiveTooLarge
    case malformedArchive
    case unsupportedArchive
    case extractionFailed
    case invalidImage(String)
    case imageTooLarge(String)
    case checksumMismatch(String)
    case alreadyInstalled
    case versionNotNewer
    case builtInIdentifier
    case identifierMismatch
    case packNotFound

    var errorDescription: String? {
        switch self {
        case .notPackage: L10n.text("pack.error.not_package")
        case .symbolicLink: L10n.text("pack.error.symbolic_link")
        case .missingManifest: L10n.text("pack.error.missing_manifest")
        case .manifestTooLarge: L10n.text("pack.error.manifest_too_large")
        case .malformedManifest: L10n.text("pack.error.malformed_manifest")
        case let .unsupportedSchema(version): L10n.text("pack.error.unsupported_schema", version)
        case .invalidIdentifier: L10n.text("pack.error.invalid_identifier")
        case .invalidVersion: L10n.text("pack.error.invalid_version")
        case let .invalidMetadata(field): L10n.text("pack.error.invalid_metadata", field)
        case let .invalidAssetPath(path): L10n.text("pack.error.invalid_asset_path", path)
        case let .missingAsset(path): L10n.text("pack.error.missing_asset", path)
        case let .unsupportedAsset(path): L10n.text("pack.error.unsupported_asset", path)
        case let .unexpectedEntry(path): L10n.text("pack.error.unexpected_entry", path)
        case .tooManyFiles: L10n.text("pack.error.too_many_files")
        case .packageTooLarge: L10n.text("pack.error.package_too_large")
        case .archiveTooLarge: L10n.text("pack.error.archive_too_large")
        case .malformedArchive: L10n.text("pack.error.malformed_archive")
        case .unsupportedArchive: L10n.text("pack.error.unsupported_archive")
        case .extractionFailed: L10n.text("pack.error.extraction_failed")
        case let .invalidImage(path): L10n.text("pack.error.invalid_image", path)
        case let .imageTooLarge(path): L10n.text("pack.error.image_too_large", path)
        case let .checksumMismatch(path): L10n.text("pack.error.checksum_mismatch", path)
        case .alreadyInstalled: L10n.text("pack.error.already_installed")
        case .versionNotNewer: L10n.text("pack.error.version_not_newer")
        case .builtInIdentifier: L10n.text("pack.error.built_in_identifier")
        case .identifierMismatch: L10n.text("pack.error.identifier_mismatch")
        case .packNotFound: L10n.text("pack.error.pack_not_found")
        }
    }
}

struct CoverPackValidator: @unchecked Sendable {
    static let maximumManifestBytes: Int64 = 64 * 1024
    static let maximumPackageBytes: Int64 = 80 * 1024 * 1024
    static let maximumFileCount = 16
    static let maximumImageDimension = 8_192

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func validate(at packageURL: URL) throws -> ValidatedCoverPack {
        let packageURL = packageURL.standardizedFileURL
        let packageValues = try packageURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard packageURL.pathExtension.lowercased() == "ortupack", packageValues.isDirectory == true else {
            throw CoverPackError.notPackage
        }
        guard packageValues.isSymbolicLink != true else { throw CoverPackError.symbolicLink }

        let entries = try fileManager.contentsOfDirectory(
            at: packageURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        )
        guard entries.count <= Self.maximumFileCount else { throw CoverPackError.tooManyFiles }

        let manifestURL = packageURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else { throw CoverPackError.missingManifest }
        let manifestValues = try manifestURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        guard manifestValues.isSymbolicLink != true else { throw CoverPackError.symbolicLink }
        guard Int64(manifestValues.fileSize ?? 0) <= Self.maximumManifestBytes else {
            throw CoverPackError.manifestTooLarge
        }

        let manifest: CoverPackManifest
        do {
            manifest = try JSONDecoder().decode(CoverPackManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw CoverPackError.malformedManifest
        }
        try validate(manifest: manifest)
        for filename in manifest.assets.allFilenames {
            try validateAssetFilename(filename)
        }

        let allowedEntries = Set(manifest.assets.allFilenames + ["manifest.json", "LICENSE.txt"])
        var totalBytes: Int64 = 0
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw CoverPackError.symbolicLink }
            guard values.isDirectory != true else { throw CoverPackError.unexpectedEntry(entry.lastPathComponent) }
            guard allowedEntries.contains(entry.lastPathComponent) else {
                throw CoverPackError.unexpectedEntry(entry.lastPathComponent)
            }
            totalBytes += Int64(values.fileSize ?? 0)
            guard totalBytes <= Self.maximumPackageBytes else { throw CoverPackError.packageTooLarge }
        }

        for filename in manifest.assets.allFilenames {
            let assetURL = packageURL.appendingPathComponent(filename, isDirectory: false)
            guard fileManager.fileExists(atPath: assetURL.path) else { throw CoverPackError.missingAsset(filename) }
            try validateImage(at: assetURL, filename: filename)
        }

        if let checksums = manifest.sha256 {
            for (filename, expectedHash) in checksums {
                try validateAssetFilename(filename)
                let fileURL = packageURL.appendingPathComponent(filename, isDirectory: false)
                guard fileManager.fileExists(atPath: fileURL.path) else { throw CoverPackError.missingAsset(filename) }
                let digest = SHA256.hash(data: try Data(contentsOf: fileURL))
                let actualHash = digest.map { String(format: "%02x", $0) }.joined()
                guard actualHash.caseInsensitiveCompare(expectedHash) == .orderedSame else {
                    throw CoverPackError.checksumMismatch(filename)
                }
            }
        }

        return ValidatedCoverPack(url: packageURL, manifest: manifest, totalBytes: totalBytes)
    }

    private func validate(manifest: CoverPackManifest) throws {
        guard manifest.schemaVersion == 1 else { throw CoverPackError.unsupportedSchema(manifest.schemaVersion) }
        guard matches(#"^[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+$"#, value: manifest.id) else {
            throw CoverPackError.invalidIdentifier
        }
        guard matches(#"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$"#, value: manifest.version) else {
            throw CoverPackError.invalidVersion
        }
        guard !manifest.name.isEmpty,
            manifest.name.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else {
            throw CoverPackError.invalidMetadata("name")
        }
        guard !manifest.author.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw CoverPackError.invalidMetadata("author")
        }
        guard ["CC0-1.0", "CC-BY-4.0", "MIT"].contains(manifest.license) else {
            throw CoverPackError.invalidMetadata("license")
        }
        guard (1 ... Self.maximumImageDimension).contains(manifest.canvas.width),
            (1 ... Self.maximumImageDimension).contains(manifest.canvas.height)
        else {
            throw CoverPackError.invalidMetadata("canvas")
        }
        guard manifest.anchor == "topCenter" else { throw CoverPackError.invalidMetadata("anchor") }
        guard (0.20 ... 0.85).contains(manifest.defaultDrop) else {
            throw CoverPackError.invalidMetadata("defaultDrop")
        }
        guard (0.20 ... 1.0).contains(manifest.defaultWidth) else {
            throw CoverPackError.invalidMetadata("defaultWidth")
        }
        guard ["multiply", "original"].contains(manifest.tintMode) else {
            throw CoverPackError.invalidMetadata("tintMode")
        }
        guard Set(manifest.assets.allFilenames).count == manifest.assets.allFilenames.count else {
            throw CoverPackError.invalidMetadata("assets")
        }
    }

    private func validateAssetFilename(_ filename: String) throws {
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
            filename != ".",
            filename != "..",
            !filename.contains("/")
        else {
            throw CoverPackError.invalidAssetPath(filename)
        }
        guard ["png", "heic", "heif"].contains(URL(fileURLWithPath: filename).pathExtension.lowercased()) else {
            throw CoverPackError.unsupportedAsset(filename)
        }
    }

    private func validateImage(at url: URL, filename: String) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0,
            height > 0
        else {
            throw CoverPackError.invalidImage(filename)
        }
        guard width <= Self.maximumImageDimension, height <= Self.maximumImageDimension else {
            throw CoverPackError.imageTooLarge(filename)
        }
    }

    private func matches(_ pattern: String, value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
