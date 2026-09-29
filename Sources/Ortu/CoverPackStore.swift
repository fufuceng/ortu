import Foundation

protocol CoverPackStoring: Actor {
    func installedPackCount() -> Int
    func availablePacks() -> [CoverPackSummary]
    func importPack(from sourceURL: URL, replacingID expectedID: String?) throws -> CoverPackImportResult
    func removePack(id: String) throws
}

struct CoverPackSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let author: String
    let version: String
    let isBuiltIn: Bool
    let packageURL: URL
    let defaultDrop: Double
    let defaultWidth: Double
    let supportsTint: Bool
    let textureURL: URL
    let previewURL: URL?
}

enum CoverPackImportAction: Equatable, Sendable {
    case installed
    case updated
}

struct CoverPackImportResult: Sendable {
    let pack: ValidatedCoverPack
    let action: CoverPackImportAction
}

actor CoverPackStore: CoverPackStoring {
    private let fileManager: FileManager
    private let validator: CoverPackValidator
    private let archive: CoverPackArchive
    private let packsDirectory: URL

    init(
        fileManager: FileManager = .default,
        validator: CoverPackValidator? = nil,
        packsDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.validator = validator ?? CoverPackValidator(fileManager: fileManager)
        archive = CoverPackArchive(fileManager: fileManager)

        if let packsDirectory {
            self.packsDirectory = packsDirectory
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.packsDirectory =
                applicationSupport
                .appendingPathComponent("Örtü", isDirectory: true)
                .appendingPathComponent("Packs", isDirectory: true)
        }
    }

    func installedPackCount() -> Int {
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: packsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return 0 }
        return entries.filter { $0.pathExtension.lowercased() == "ortupack" }.count
    }

    func availablePacks() -> [CoverPackSummary] {
        let builtInURLs = builtInPackURLs()
        var packageURLs = builtInURLs.map { ($0, true) }

        if let installed = try? fileManager.contentsOfDirectory(
            at: packsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            packageURLs.append(
                contentsOf:
                    installed
                    .filter { $0.pathExtension.lowercased() == "ortupack" }
                    .map { ($0, false) })
        }

        return packageURLs.compactMap { packageURL, isBuiltIn in
            guard let validated = try? validator.validate(at: packageURL) else { return nil }
            let manifest = validated.manifest
            let localizedName =
                manifest.name[Locale.current.language.languageCode?.identifier ?? ""]
                ?? manifest.name["en"]
                ?? manifest.name.values.first
                ?? manifest.id
            return CoverPackSummary(
                id: manifest.id,
                name: localizedName,
                author: manifest.author,
                version: manifest.version,
                isBuiltIn: isBuiltIn,
                packageURL: packageURL,
                defaultDrop: manifest.defaultDrop,
                defaultWidth: manifest.defaultWidth,
                supportsTint: manifest.tintMode == "multiply",
                textureURL: packageURL.appendingPathComponent(manifest.assets.texture2x),
                previewURL: manifest.assets.preview.map { packageURL.appendingPathComponent($0) }
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func builtInPackURLs() -> [URL] {
        guard
            let seedPack = Bundle.module.url(
                forResource: "Inci",
                withExtension: "ortupack",
                subdirectory: "BuiltinPacks"
            )
        else { return [] }
        let directory = seedPack.deletingLastPathComponent()
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        return entries.filter { $0.pathExtension.lowercased() == "ortupack" }
    }

    @discardableResult
    func importPack(
        from sourceURL: URL,
        replacingID expectedID: String? = nil
    ) throws -> CoverPackImportResult {
        try fileManager.createDirectory(at: packsDirectory, withIntermediateDirectories: true)

        let sourceValues = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
        let staging = packsDirectory.appendingPathComponent(
            ".import-\(UUID().uuidString).ortupack",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: staging) }

        let validated: ValidatedCoverPack
        if sourceValues.isDirectory == true {
            validated = try validator.validate(at: sourceURL)
            try fileManager.copyItem(at: sourceURL, to: staging)
        } else {
            try archive.extract(sourceURL, to: staging)
            validated = try validator.validate(at: staging)
        }
        if let expectedID, validated.manifest.id != expectedID {
            throw CoverPackError.identifierMismatch
        }

        let destination = packsDirectory.appendingPathComponent(
            "\(validated.manifest.id).ortupack",
            isDirectory: true
        )
        let builtInIDs = Set(
            builtInPackURLs().compactMap {
                try? validator.validate(at: $0).manifest.id
            })
        guard !builtInIDs.contains(validated.manifest.id) else {
            throw CoverPackError.builtInIdentifier
        }

        _ = try validator.validate(at: staging)
        let action: CoverPackImportAction
        if fileManager.fileExists(atPath: destination.path) {
            let current = try validator.validate(at: destination)
            guard current.manifest.version != validated.manifest.version else {
                throw CoverPackError.alreadyInstalled
            }
            guard SemanticVersion(validated.manifest.version) > SemanticVersion(current.manifest.version) else {
                throw CoverPackError.versionNotNewer
            }
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
            action = .updated
        } else {
            try fileManager.moveItem(at: staging, to: destination)
            action = .installed
        }

        return CoverPackImportResult(
            pack: try validator.validate(at: destination),
            action: action
        )
    }

    func removePack(id: String) throws {
        let destination = packsDirectory.appendingPathComponent("\(id).ortupack", isDirectory: true)
        guard fileManager.fileExists(atPath: destination.path) else { throw CoverPackError.packNotFound }
        let installed = try validator.validate(at: destination)
        guard installed.manifest.id == id else { throw CoverPackError.packNotFound }
        try fileManager.removeItem(at: destination)
    }
}

private struct SemanticVersion: Comparable {
    private let core: [Int]
    private let prerelease: [String]?

    init(_ value: String) {
        let withoutBuild = value.split(separator: "+", maxSplits: 1).first.map(String.init) ?? value
        let parts = withoutBuild.split(separator: "-", maxSplits: 1).map(String.init)
        core = parts[0].split(separator: ".").map { Int($0) ?? 0 }
        prerelease = parts.count == 2 ? parts[1].split(separator: ".").map(String.init) : nil
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0 ..< max(lhs.core.count, rhs.core.count) {
            let left = index < lhs.core.count ? lhs.core[index] : 0
            let right = index < rhs.core.count ? rhs.core[index] : 0
            if left != right { return left < right }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (.some, nil): return true
        case (nil, .some): return false
        case let (.some(left), .some(right)):
            for index in 0 ..< max(left.count, right.count) {
                guard index < left.count else { return true }
                guard index < right.count else { return false }
                if left[index] == right[index] { continue }
                if let leftNumber = Int(left[index]), let rightNumber = Int(right[index]) {
                    return leftNumber < rightNumber
                }
                if Int(left[index]) != nil { return true }
                if Int(right[index]) != nil { return false }
                return left[index] < right[index]
            }
            return false
        }
    }
}
