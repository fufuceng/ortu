import Foundation

struct CoverPackArchive {
    static let maximumArchiveBytes: Int64 = 25 * 1024 * 1024

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func extract(_ archiveURL: URL, to destinationURL: URL) throws {
        try inspect(archiveURL)
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CoverPackError.extractionFailed
        }
        guard process.terminationStatus == 0 else {
            throw CoverPackError.extractionFailed
        }
    }

    func inspect(_ archiveURL: URL) throws {
        let values = try archiveURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard archiveURL.pathExtension.lowercased() == "ortupack",
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw CoverPackError.notPackage
        }
        guard Int64(values.fileSize ?? 0) <= Self.maximumArchiveBytes else {
            throw CoverPackError.archiveTooLarge
        }

        let data = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        let endRecord = try findEndOfCentralDirectory(in: data)
        let diskNumber = try data.uint16(at: endRecord + 4)
        let centralDirectoryDisk = try data.uint16(at: endRecord + 6)
        let entriesOnDisk = try data.uint16(at: endRecord + 8)
        let entryCount = try data.uint16(at: endRecord + 10)
        let centralDirectorySize = try data.uint32(at: endRecord + 12)
        let centralDirectoryOffset = try data.uint32(at: endRecord + 16)

        guard diskNumber == 0,
            centralDirectoryDisk == 0,
            entriesOnDisk == entryCount,
            entryCount > 0,
            entryCount != UInt16.max,
            entryCount <= CoverPackValidator.maximumFileCount,
            centralDirectorySize != UInt32.max,
            centralDirectoryOffset != UInt32.max
        else {
            throw CoverPackError.unsupportedArchive
        }

        let directoryStart = Int(centralDirectoryOffset)
        let directoryEnd = directoryStart + Int(centralDirectorySize)
        guard directoryStart >= 0, directoryEnd <= data.count else {
            throw CoverPackError.malformedArchive
        }

        var offset = directoryStart
        var filenames = Set<String>()
        var totalUncompressedBytes: Int64 = 0

        for _ in 0 ..< Int(entryCount) {
            guard try data.uint32(at: offset) == 0x02014B50 else {
                throw CoverPackError.malformedArchive
            }

            let versionMadeBy = try data.uint16(at: offset + 4)
            let flags = try data.uint16(at: offset + 8)
            let compressionMethod = try data.uint16(at: offset + 10)
            let compressedSize = try data.uint32(at: offset + 20)
            let uncompressedSize = try data.uint32(at: offset + 24)
            let filenameLength = Int(try data.uint16(at: offset + 28))
            let extraLength = Int(try data.uint16(at: offset + 30))
            let commentLength = Int(try data.uint16(at: offset + 32))
            let externalAttributes = try data.uint32(at: offset + 38)
            let localHeaderOffset = try data.uint32(at: offset + 42)
            let recordEnd = offset + 46 + filenameLength + extraLength + commentLength

            guard recordEnd <= directoryEnd,
                compressedSize != UInt32.max,
                uncompressedSize != UInt32.max,
                flags & 0x1 == 0,
                compressionMethod == 0 || compressionMethod == 8
            else {
                throw CoverPackError.unsupportedArchive
            }

            let filenameRange = (offset + 46) ..< (offset + 46 + filenameLength)
            guard let filename = String(data: data[filenameRange], encoding: .utf8),
                isSafeRootFilename(filename),
                isAllowedFilename(filename),
                filenames.insert(filename.precomposedStringWithCanonicalMapping.lowercased()).inserted
            else {
                throw CoverPackError.unsupportedArchive
            }
            try validateLocalHeader(
                in: data,
                at: Int(localHeaderOffset),
                expectedFilename: filename,
                expectedMethod: compressionMethod,
                expectedFlags: flags
            )

            let hostSystem = versionMadeBy >> 8
            let unixMode = externalAttributes >> 16
            if hostSystem == 3, unixMode & 0o170000 == 0o120000 {
                throw CoverPackError.symbolicLink
            }

            totalUncompressedBytes += Int64(uncompressedSize)
            guard totalUncompressedBytes <= CoverPackValidator.maximumPackageBytes else {
                throw CoverPackError.packageTooLarge
            }
            offset = recordEnd
        }

        guard offset == directoryEnd else { throw CoverPackError.malformedArchive }
    }

    private func findEndOfCentralDirectory(in data: Data) throws -> Int {
        guard data.count >= 22 else { throw CoverPackError.malformedArchive }
        let minimumOffset = max(0, data.count - 22 - 65_535)
        var offset = data.count - 22
        while offset >= minimumOffset {
            if (try? data.uint32(at: offset)) == 0x06054B50 {
                let commentLength = Int(try data.uint16(at: offset + 20))
                guard offset + 22 + commentLength == data.count else {
                    throw CoverPackError.malformedArchive
                }
                return offset
            }
            offset -= 1
        }
        throw CoverPackError.malformedArchive
    }

    private func isSafeRootFilename(_ filename: String) -> Bool {
        guard !filename.isEmpty,
            filename != ".",
            filename != "..",
            !filename.hasPrefix("."),
            !filename.contains("/"),
            !filename.contains("\\"),
            !filename.contains(":"),
            filename.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }),
            filename == URL(fileURLWithPath: filename).lastPathComponent
        else {
            return false
        }
        return true
    }

    private func isAllowedFilename(_ filename: String) -> Bool {
        if filename == "manifest.json" || filename == "LICENSE.txt" { return true }
        return ["png", "heic", "heif"].contains(
            URL(fileURLWithPath: filename).pathExtension.lowercased()
        )
    }

    private func validateLocalHeader(
        in data: Data,
        at offset: Int,
        expectedFilename: String,
        expectedMethod: UInt16,
        expectedFlags: UInt16
    ) throws {
        guard try data.uint32(at: offset) == 0x04034B50 else {
            throw CoverPackError.malformedArchive
        }
        let flags = try data.uint16(at: offset + 6)
        let method = try data.uint16(at: offset + 8)
        let filenameLength = Int(try data.uint16(at: offset + 26))
        let extraLength = Int(try data.uint16(at: offset + 28))
        let filenameStart = offset + 30
        let filenameEnd = filenameStart + filenameLength
        guard filenameEnd + extraLength <= data.count,
            let filename = String(data: data[filenameStart ..< filenameEnd], encoding: .utf8),
            filename == expectedFilename,
            flags == expectedFlags,
            method == expectedMethod
        else {
            throw CoverPackError.malformedArchive
        }
    }
}

private extension Data {
    func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw CoverPackError.malformedArchive }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw CoverPackError.malformedArchive }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
