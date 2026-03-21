import Foundation
import Photos
import Testing

@testable import LadderKit

/// Mock script exporter that writes a known file to the target directory.
struct MockScriptExporter: ScriptExporter {
    /// Map of UUID → (filename, data) for assets the mock can export.
    let assets: [String: (filename: String, data: Data)]
    /// If set, all exports throw this error.
    var error: (any Error)?

    func checkPermissions() async throws {}

    func exportAsset(
        identifier: String,
        to directory: URL,
        timeout: TimeInterval
    ) async throws -> URL {
        if let error { throw error }

        let bareUUID = stripLocalIdSuffix(identifier)
        guard let (filename, data) = assets[bareUUID] ?? assets[identifier] else {
            throw AppleScriptError.noFileProduced(bareUUID)
        }

        // Mimic AppleScript: create subdirectory and write file
        let subdir = directory.appendingPathComponent("as_\(bareUUID)")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let fileURL = subdir.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }
}

/// Mock asset handle that always fails (simulates iCloud download failure).
struct FailingAssetHandle: AssetHandle {
    let originalFilename: String
    let resourceType: PHAssetResourceType = .photo

    func writeData(
        to destinationURL: URL,
        networkAccessAllowed: Bool,
        chunkHandler: @escaping @Sendable (Data) -> Void
    ) async throws -> Int64 {
        throw NSError(domain: "PHPhotosErrorDomain", code: 3169)
    }
}

@Suite("AppleScript Exporter")
struct AppleScriptExporterTests {

    // MARK: - stripLocalIdSuffix

    @Test("strips /L0/001 suffix from PhotoKit identifier")
    func stripSuffix() {
        #expect(stripLocalIdSuffix("8A3B1C2D-4E5F-6789-ABCD-EF0123456789/L0/001")
            == "8A3B1C2D-4E5F-6789-ABCD-EF0123456789")
    }

    @Test("returns bare UUID unchanged")
    func bareUUID() {
        #expect(stripLocalIdSuffix("8A3B1C2D-4E5F-6789-ABCD-EF0123456789")
            == "8A3B1C2D-4E5F-6789-ABCD-EF0123456789")
    }

    // MARK: - buildExportScript

    @Test("builds correct AppleScript")
    func exportScript() {
        let script = buildExportScript(
            uuid: "ABC-123",
            destination: "/tmp/staging/as_ABC-123"
        )
        #expect(script.contains("media item id \"ABC-123\""))
        #expect(script.contains("POSIX file \"/tmp/staging/as_ABC-123\""))
        #expect(script.contains("with using originals"))
    }

    // MARK: - PhotoExporter with script fallback

    @Test("falls back to AppleScript for missing UUIDs")
    func fallbackForMissing() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ladder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testData = Data("icloud photo data".utf8)
        let scriptExporter = MockScriptExporter(assets: [
            "missing-uuid": ("IMG_5678.HEIC", testData),
        ])

        let library = MockPhotoLibrary(assets: [:])
        let exporter = PhotoExporter(
            stagingDir: tempDir,
            library: library,
            scriptExporter: scriptExporter
        )

        let response = await exporter.export(uuids: ["missing-uuid"])

        #expect(response.results.count == 1)
        #expect(response.errors.isEmpty)

        let result = response.results[0]
        #expect(result.uuid == "missing-uuid")
        #expect(result.size == Int64(testData.count))
        #expect(!result.sha256.isEmpty)
    }

    @Test("PhotoKit assets export normally, missing ones fall back to AppleScript")
    func mixedPhotoKitAndAppleScript() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ladder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let photoKitData = Data("photokit data".utf8)
        let appleScriptData = Data("applescript data".utf8)

        let library = MockPhotoLibrary(assets: [
            "local-uuid": MockAssetHandle(
                originalFilename: "IMG_0001.HEIC",
                resourceType: .photo,
                data: photoKitData
            ),
        ])

        let scriptExporter = MockScriptExporter(assets: [
            "icloud-uuid": ("IMG_9999.HEIC", appleScriptData),
        ])

        let exporter = PhotoExporter(
            stagingDir: tempDir,
            library: library,
            scriptExporter: scriptExporter
        )

        let response = await exporter.export(uuids: ["local-uuid", "icloud-uuid"])

        #expect(response.results.count == 2)
        #expect(response.errors.isEmpty)

        let uuids = Set(response.results.map(\.uuid))
        #expect(uuids.contains("local-uuid"))
        #expect(uuids.contains("icloud-uuid"))
    }

    @Test("without script exporter, missing UUIDs reported as errors (original behavior)")
    func noFallbackWithoutScriptExporter() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ladder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = MockPhotoLibrary(assets: [:])
        let exporter = PhotoExporter(
            stagingDir: tempDir,
            library: library,
            scriptExporter: nil
        )

        let response = await exporter.export(uuids: ["missing-uuid"])

        #expect(response.results.isEmpty)
        #expect(response.errors.count == 1)
        #expect(response.errors[0].uuid == "missing-uuid")
        #expect(response.errors[0].message == "Asset not found in Photos library")
    }

    @Test("script export error reported as ExportError")
    func scriptExportError() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ladder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scriptExporter = MockScriptExporter(
            assets: [:],
            error: AppleScriptError.automationPermissionDenied
        )

        let library = MockPhotoLibrary(assets: [:])
        let exporter = PhotoExporter(
            stagingDir: tempDir,
            library: library,
            scriptExporter: scriptExporter
        )

        let response = await exporter.export(uuids: ["icloud-uuid"])

        #expect(response.results.isEmpty)
        #expect(response.errors.count == 1)
        #expect(response.errors[0].uuid == "icloud-uuid")
        #expect(response.errors[0].message.contains("Automation permission"))
    }

    @Test("UUID /L0/001 suffix stripped for AppleScript export")
    func suffixStrippedForFallback() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ladder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testData = Data("data".utf8)
        // Register with bare UUID — the exporter should strip the suffix
        let scriptExporter = MockScriptExporter(assets: [
            "ABC-123": ("IMG_0001.HEIC", testData),
        ])

        let library = MockPhotoLibrary(assets: [:])
        let exporter = PhotoExporter(
            stagingDir: tempDir,
            library: library,
            scriptExporter: scriptExporter
        )

        let response = await exporter.export(uuids: ["ABC-123/L0/001"])

        #expect(response.results.count == 1)
        #expect(response.results[0].uuid == "ABC-123/L0/001")
    }

    @Test("PhotoKit export failure falls back to AppleScript")
    func photoKitFailureFallsBackToAppleScript() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ladder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appleScriptData = Data("recovered via applescript".utf8)

        // PhotoKit finds the asset but writeData throws (simulates iCloud download failure)
        let library = MockPhotoLibrary(assets: [
            "fail-uuid": FailingAssetHandle(originalFilename: "IMG_FAIL.HEIC"),
        ])

        let scriptExporter = MockScriptExporter(assets: [
            "fail-uuid": ("IMG_FAIL.HEIC", appleScriptData),
        ])

        let exporter = PhotoExporter(
            stagingDir: tempDir,
            library: library,
            scriptExporter: scriptExporter
        )

        let response = await exporter.export(uuids: ["fail-uuid"])

        // Should succeed via AppleScript fallback, not fail
        #expect(response.results.count == 1)
        #expect(response.errors.isEmpty)
        #expect(response.results[0].uuid == "fail-uuid")
    }

    // MARK: - Error types

    @Test("AppleScriptError provides descriptive messages")
    func errorMessages() {
        let errors: [AppleScriptError] = [
            .automationPermissionDenied,
            .timeout("UUID-123", 600),
            .scriptFailed("UUID-123", "some error"),
            .noFileProduced("UUID-123"),
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }

        #expect(AppleScriptError.timeout("X", 600).errorDescription!.contains("600"))
        #expect(AppleScriptError.automationPermissionDenied.errorDescription!.contains("Automation"))
    }

    // MARK: - AppleScript escaping

    @Test("buildExportScript escapes quotes in UUID")
    func scriptEscapesQuotes() {
        let script = buildExportScript(
            uuid: #"ABC" & evil & ""#,
            destination: "/tmp/safe"
        )
        // The quote should be escaped, not terminating the string
        #expect(script.contains(#"ABC\" & evil & \""#))
        #expect(!script.contains(#"id "ABC" & evil"#))
    }

    @Test("buildExportScript escapes backslashes in destination")
    func scriptEscapesBackslashes() {
        let script = buildExportScript(
            uuid: "ABC-123",
            destination: #"/tmp/path\with\backslashes"#
        )
        #expect(script.contains(#"path\\with\\backslashes"#))
    }

    // MARK: - UUID validation

    @Test("isValidBareUUID accepts standard UUIDs")
    func validUUIDs() {
        #expect(isValidBareUUID("8A3B1C2D-4E5F-6789-ABCD-EF0123456789"))
        #expect(isValidBareUUID("b84e8479-475c-4727-a7f4-b3d5e5d71923"))
    }

    @Test("isValidBareUUID rejects malformed strings")
    func invalidUUIDs() {
        #expect(!isValidBareUUID("not-a-uuid"))
        #expect(!isValidBareUUID(""))
        #expect(!isValidBareUUID(#"ABC" & do shell script "evil" & ""#))
        #expect(!isValidBareUUID("8A3B1C2D-4E5F-6789-ABCD-EF0123456789/L0/001"))
    }
}
