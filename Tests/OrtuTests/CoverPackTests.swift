import Foundation
import Testing
@testable import Ortu

@Suite("Cover pack validation")
struct CoverPackTests {
    @Test("A valid data-only package is accepted")
    func validPackage() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage(in: root)

        let validated = try CoverPackValidator().validate(at: package)

        #expect(validated.manifest.id == "dev.ortu.sample")
        #expect(validated.totalBytes > 0)
    }

    @Test("Unexpected executable content is rejected")
    func rejectsUnexpectedContent() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage(in: root)
        try Data("alert('no')".utf8).write(to: package.appendingPathComponent("script.js"))

        do {
            _ = try CoverPackValidator().validate(at: package)
            Issue.record("Validator accepted unexpected executable content")
        } catch let error as CoverPackError {
            #expect(error == .unexpectedEntry("script.js"))
        }
    }

    @Test("Hidden content is rejected instead of being ignored")
    func rejectsHiddenContent() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage(in: root)
        try Data("metadata".utf8).write(to: package.appendingPathComponent(".hidden"))

        do {
            _ = try CoverPackValidator().validate(at: package)
            Issue.record("Validator ignored hidden package content")
        } catch let error as CoverPackError {
            #expect(error == .unexpectedEntry(".hidden"))
        }
    }

    @Test("Traversal paths are rejected")
    func rejectsTraversal() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = sampleManifest(
            assets: .init(
                texture1x: "../outside.png",
                texture2x: "texture@2x.png",
                mask: "mask.png",
                preview: nil
            )
        )
        let package = try makePackage(in: root, manifest: manifest)

        do {
            _ = try CoverPackValidator().validate(at: package)
            Issue.record("Validator accepted a traversal path")
        } catch let error as CoverPackError {
            #expect(error == .invalidAssetPath("../outside.png"))
        }
    }

    @Test("Checksum mismatches are rejected")
    func rejectsChecksumMismatch() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = sampleManifest(
            checksums: ["mask.png": String(repeating: "0", count: 64)]
        )
        let package = try makePackage(in: root, manifest: manifest)

        do {
            _ = try CoverPackValidator().validate(at: package)
            Issue.record("Validator accepted an invalid checksum")
        } catch let error as CoverPackError {
            #expect(error == .checksumMismatch("mask.png"))
        }
    }

    @Test("Import is atomic and rejects duplicate IDs")
    func importsOnce() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Installed", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let package = try makePackage(in: sourceRoot)
        let store = CoverPackStore(packsDirectory: destination)

        _ = try await store.importPack(from: package)
        #expect(await store.installedPackCount() == 1)

        do {
            _ = try await store.importPack(from: package)
            Issue.record("Store installed a duplicate package")
        } catch let error as CoverPackError {
            #expect(error == .alreadyInstalled)
        }
    }

    @Test("A ZIP transport is inspected, expanded, and installed")
    func importsArchive() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Installed", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let package = try makePackage(in: sourceRoot)
        let archive = root.appendingPathComponent("Sample.ortupack")
        try makeArchive(from: package, at: archive)

        let result = try await CoverPackStore(packsDirectory: destination).importPack(from: archive)
        let installed = result.pack

        #expect(installed.manifest.id == "dev.ortu.sample")
        #expect(result.action == .installed)
        #expect(installed.url.hasDirectoryPath)
        #expect(
            FileManager.default.fileExists(
                atPath: installed.url.appendingPathComponent("manifest.json").path
            ))
    }

    @Test("Malformed archives are rejected without leaving staging files")
    func rejectsMalformedArchiveAtomically() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Installed", isDirectory: true)
        let archive = root.appendingPathComponent("Broken.ortupack")
        try Data("not a zip".utf8).write(to: archive)
        let store = CoverPackStore(packsDirectory: destination)

        do {
            _ = try await store.importPack(from: archive)
            Issue.record("Store imported a malformed archive")
        } catch let error as CoverPackError {
            #expect(error == .malformedArchive)
        }

        let leftovers = try FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: nil
        )
        #expect(leftovers.isEmpty)
    }

    @Test("Encrypted archive entries are rejected before extraction")
    func rejectsEncryptedArchive() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage(in: root)
        let archive = root.appendingPathComponent("Encrypted.ortupack")
        try runZip(
            in: package,
            arguments: ["-X", "-q", "-P", "secret", archive.path, "manifest.json"]
        )

        #expect(throws: CoverPackError.unsupportedArchive) {
            try CoverPackArchive().inspect(archive)
        }
    }

    @Test("Local and central ZIP header filename mismatches are rejected")
    func rejectsHeaderMismatch() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage(in: root)
        let archive = root.appendingPathComponent("Mismatch.ortupack")
        try makeArchive(from: package, at: archive)
        var data = try Data(contentsOf: archive)
        let filename = try #require(data.range(of: Data("manifest.json".utf8)))
        data[filename.lowerBound] = Character("x").asciiValue ?? 120
        try data.write(to: archive, options: .atomic)

        #expect(throws: CoverPackError.malformedArchive) {
            try CoverPackArchive().inspect(archive)
        }
    }

    @Test("Declared ZIP expansion beyond the package limit is rejected")
    func rejectsExpansionLimit() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage(in: root)
        let archive = root.appendingPathComponent("Oversized.ortupack")
        try makeArchive(from: package, at: archive)
        var data = try Data(contentsOf: archive)
        let centralHeader = try #require(data.range(of: Data([0x50, 0x4B, 0x01, 0x02])))
        data.writeLittleEndian(
            UInt32(CoverPackValidator.maximumPackageBytes + 1),
            at: centralHeader.lowerBound + 24
        )
        try data.write(to: archive, options: .atomic)

        #expect(throws: CoverPackError.packageTooLarge) {
            try CoverPackArchive().inspect(archive)
        }
    }

    @Test("Symbolic links in ZIP transports are rejected")
    func rejectsArchiveSymlink() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("target".utf8).write(to: source.appendingPathComponent("target.png"))
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("linked.png"),
            withDestinationURL: source.appendingPathComponent("target.png")
        )
        let archive = root.appendingPathComponent("Symlink.ortupack")
        try runZip(in: source, arguments: ["-X", "-q", "-y", archive.path, "linked.png"])

        #expect(throws: CoverPackError.symbolicLink) {
            try CoverPackArchive().inspect(archive)
        }
    }

    @Test("A newer version atomically replaces an installed package")
    func updatesInstalledPackage() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstRoot = root.appendingPathComponent("First", isDirectory: true)
        let updateRoot = root.appendingPathComponent("Update", isDirectory: true)
        let destination = root.appendingPathComponent("Installed", isDirectory: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: updateRoot, withIntermediateDirectories: true)
        let first = try makePackage(in: firstRoot)
        let update = try makePackage(in: updateRoot, manifest: sampleManifest(version: "1.1.0"))
        let store = CoverPackStore(packsDirectory: destination)

        _ = try await store.importPack(from: first)
        let result = try await store.importPack(from: update, replacingID: "dev.ortu.sample")

        #expect(result.action == .updated)
        #expect(result.pack.manifest.version == "1.1.0")
        #expect(await store.installedPackCount() == 1)
    }

    @Test("An older version cannot replace the installed package")
    func rejectsPackageDowngrade() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstRoot = root.appendingPathComponent("First", isDirectory: true)
        let olderRoot = root.appendingPathComponent("Older", isDirectory: true)
        let destination = root.appendingPathComponent("Installed", isDirectory: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: olderRoot, withIntermediateDirectories: true)
        let first = try makePackage(in: firstRoot, manifest: sampleManifest(version: "2.0.0"))
        let older = try makePackage(in: olderRoot, manifest: sampleManifest(version: "1.9.0"))
        let store = CoverPackStore(packsDirectory: destination)
        _ = try await store.importPack(from: first)

        do {
            _ = try await store.importPack(from: older, replacingID: "dev.ortu.sample")
            Issue.record("Store accepted a package downgrade")
        } catch let error as CoverPackError {
            #expect(error == .versionNotNewer)
        }

        #expect(await store.availablePacks().first(where: { $0.id == "dev.ortu.sample" })?.version == "2.0.0")
    }

    @Test("Package removal only targets validated user packages")
    func removesInstalledPackage() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Installed", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let package = try makePackage(in: sourceRoot)
        let store = CoverPackStore(packsDirectory: destination)
        _ = try await store.importPack(from: package)

        try await store.removePack(id: "dev.ortu.sample")

        #expect(await store.installedPackCount() == 0)
    }

    @Test("All built-in packages are valid and available")
    func bundledPackIsAvailable() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CoverPackStore(packsDirectory: root)

        let packs = await store.availablePacks()

        #expect(packs.count == 7)
        #expect(
            Set(packs.map(\.id)) == [
                "dev.ortu.inci",
                "dev.ortu.karanfil",
                "dev.ortu.lale",
                "dev.ortu.papatya",
                "dev.ortu.rumi",
                "dev.ortu.selcuk",
                "dev.ortu.yildiz",
            ])
        #expect(packs.allSatisfy { $0.textureURL.pathExtension == "png" })
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ortu-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePackage(
        in root: URL,
        manifest: CoverPackManifest = sampleManifest()
    ) throws -> URL {
        let package = root.appendingPathComponent("Sample.ortupack", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        try Data("CC0-1.0".utf8).write(to: package.appendingPathComponent("LICENSE.txt"))

        let png = try #require(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
        )
        for filename in ["texture@1x.png", "texture@2x.png", "mask.png"] {
            try png.write(to: package.appendingPathComponent(filename))
        }
        return package
    }

    private func makeArchive(from package: URL, at archive: URL) throws {
        try runZip(
            in: package,
            arguments: [
                "-X", "-q", archive.path,
                "manifest.json", "LICENSE.txt", "texture@1x.png", "texture@2x.png", "mask.png",
            ]
        )
    }

    private func runZip(in directory: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

}

private extension Data {
    mutating func writeLittleEndian(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        self[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        self[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}

private func sampleManifest(
    assets: CoverPackManifest.Assets = .init(
        texture1x: "texture@1x.png",
        texture2x: "texture@2x.png",
        mask: "mask.png",
        preview: nil
    ),
    checksums: [String: String]? = nil,
    version: String = "1.0.0"
) -> CoverPackManifest {
    CoverPackManifest(
        schemaVersion: 1,
        id: "dev.ortu.sample",
        version: version,
        name: ["tr": "Örnek", "en": "Sample"],
        author: "Örtü",
        license: "CC0-1.0",
        canvas: .init(width: 1, height: 1),
        anchor: "topCenter",
        defaultDrop: 0.56,
        defaultWidth: 0.90,
        tintMode: "multiply",
        assets: assets,
        sha256: checksums
    )
}
