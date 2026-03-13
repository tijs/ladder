import Foundation
import Photos
import Testing

@testable import LadderKit

/// Mock photo library for testing export logic without PhotoKit.
struct MockPhotoLibrary: PhotoLibrary {
    let assets: [String: AssetHandle]

    func fetchAssets(identifiers: [String]) -> [String: AssetHandle] {
        var result: [String: AssetHandle] = [:]
        for id in identifiers {
            if let handle = assets[id] {
                result[id] = handle
            }
        }
        return result
    }
}

/// Mock asset handle that writes known data.
struct MockAssetHandle: AssetHandle {
    let originalFilename: String
    let resourceType: PHAssetResourceType
    let data: Data

    func writeData(
        to destinationURL: URL,
        networkAccessAllowed: Bool,
        chunkHandler: @escaping @Sendable (Data) -> Void
    ) async throws -> Int64 {
        let handle = try FileHandle(forWritingTo: destinationURL)
        // Deliver in chunks to simulate streaming
        let chunkSize = max(data.count / 3, 1)
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data[offset..<end]
            chunkHandler(Data(chunk))
            handle.write(Data(chunk))
            offset = end
        }
        handle.closeFile()
        return Int64(data.count)
    }
}

@Suite("PhotoExporter")
struct PhotoExporterTests {
    @Test("exports known assets with correct hash")
    func exportKnownAssets() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ladder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testData = Data("hello world\n".utf8)

        let library = MockPhotoLibrary(assets: [
            "uuid-1": MockAssetHandle(
                originalFilename: "IMG_0001.HEIC",
                resourceType: .photo,
                data: testData
            )
        ])

        let exporter = PhotoExporter(stagingDir: tempDir, library: library)
        let response = await exporter.export(uuids: ["uuid-1"])

        #expect(response.results.count == 1)
        #expect(response.errors.isEmpty)

        let result = response.results[0]
        #expect(result.uuid == "uuid-1")
        #expect(result.size == Int64(testData.count))
        #expect(result.path.hasSuffix("uuid-1_IMG_0001.HEIC"))

        // sha256("hello world\n")
        #expect(result.sha256 == "a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447")
    }

    @Test("reports missing UUIDs as errors")
    func reportMissingUUIDs() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ladder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = MockPhotoLibrary(assets: [:])
        let exporter = PhotoExporter(stagingDir: tempDir, library: library)
        let response = await exporter.export(uuids: ["missing-uuid"])

        #expect(response.results.isEmpty)
        #expect(response.errors.count == 1)
        #expect(response.errors[0].uuid == "missing-uuid")
    }

    @Test("handles mix of found and missing assets")
    func mixedResults() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ladder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = MockPhotoLibrary(assets: [
            "found-1": MockAssetHandle(
                originalFilename: "photo.jpg",
                resourceType: .photo,
                data: Data("test".utf8)
            )
        ])

        let exporter = PhotoExporter(stagingDir: tempDir, library: library)
        let response = await exporter.export(uuids: ["found-1", "missing-1"])

        #expect(response.results.count == 1)
        #expect(response.results[0].uuid == "found-1")
        #expect(response.errors.count == 1)
        #expect(response.errors[0].uuid == "missing-1")
    }

    @Test("sanitizes PHAsset-style identifiers in file paths")
    func sanitizedPaths() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ladder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = MockPhotoLibrary(assets: [
            "ABC-123/L0/001": MockAssetHandle(
                originalFilename: "IMG_0001.HEIC",
                resourceType: .photo,
                data: Data("x".utf8)
            )
        ])

        let exporter = PhotoExporter(stagingDir: tempDir, library: library)
        let response = await exporter.export(uuids: ["ABC-123/L0/001"])

        #expect(response.results.count == 1)
        let path = response.results[0].path
        // File should be flat inside staging dir, not in subdirectories
        let filename = URL(fileURLWithPath: path).lastPathComponent
        #expect(!filename.contains("/"))
        #expect(path.hasPrefix(tempDir.path))
    }
}
