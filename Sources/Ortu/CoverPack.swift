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
        case .notPackage: "Seçilen öğe bir .ortupack paketi değil."
        case .symbolicLink: "Paket veya içindeki bir dosya sembolik bağlantı olamaz."
        case .missingManifest: "Paket manifest.json içermiyor."
        case .manifestTooLarge: "Paket manifesti izin verilen boyutu aşıyor."
        case .malformedManifest: "Paket manifesti okunamadı."
        case let .unsupportedSchema(version): "Paket şeması desteklenmiyor: \(version)."
        case .invalidIdentifier: "Paket kimliği geçersiz."
        case .invalidVersion: "Paket sürümü geçerli semantic version biçiminde değil."
        case let .invalidMetadata(field): "Paket alanı geçersiz: \(field)."
        case let .invalidAssetPath(path): "Güvenli olmayan varlık yolu: \(path)."
        case let .missingAsset(path): "Paket varlığı eksik: \(path)."
        case let .unsupportedAsset(path): "Desteklenmeyen varlık türü: \(path)."
        case let .unexpectedEntry(path): "Pakette beklenmeyen öğe var: \(path)."
        case .tooManyFiles: "Paket çok fazla dosya içeriyor."
        case .packageTooLarge: "Paket açılmış boyut sınırını aşıyor."
        case .archiveTooLarge: "Paket dosyası 25 MB sınırını aşıyor."
        case .malformedArchive: "Paket arşivi okunamadı veya bozuk."
        case .unsupportedArchive: "Paket arşivi desteklenmeyen ya da güvensiz bir özellik içeriyor."
        case .extractionFailed: "Paket güvenli kurulum alanına açılamadı."
        case let .invalidImage(path): "Görsel okunamadı: \(path)."
        case let .imageTooLarge(path): "Görsel boyutları sınırı aşıyor: \(path)."
        case let .checksumMismatch(path): "Dosya bütünlük kontrolü başarısız: \(path)."
        case .alreadyInstalled: "Bu örtü paketi zaten yüklü."
        case .versionNotNewer: "Yalnızca daha yeni bir paket sürümü yüklenebilir."
        case .builtInIdentifier: "Yerleşik bir örtünün kimliği harici paket tarafından kullanılamaz."
        case .identifierMismatch: "Seçilen dosya bu örtü paketinin yeni sürümü değil."
        case .packNotFound: "Yüklü örtü paketi bulunamadı."
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
