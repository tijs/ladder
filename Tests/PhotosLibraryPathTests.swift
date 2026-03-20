import Foundation
import Testing

@testable import LadderKit

@Suite("PhotosLibraryPath")
struct PhotosLibraryPathTests {
    @Test("databasePath returns path when database exists")
    func databasePathExists() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).photoslibrary")
        let dbDir = tempDir.appendingPathComponent("database")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbFile = dbDir.appendingPathComponent("Photos.sqlite")
        FileManager.default.createFile(atPath: dbFile.path, contents: Data())

        let result = PhotosLibraryPath.databasePath(for: tempDir)
        #expect(result == dbFile.path)
    }

    @Test("databasePath returns nil when database missing")
    func databasePathMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).photoslibrary")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = PhotosLibraryPath.databasePath(for: tempDir)
        #expect(result == nil)
    }

    @Test("validate accepts valid library bundle")
    func validateValid() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).photoslibrary")
        let dbDir = tempDir.appendingPathComponent("database")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        FileManager.default.createFile(
            atPath: dbDir.appendingPathComponent("Photos.sqlite").path,
            contents: Data()
        )

        let result = PhotosLibraryPath.validate(tempDir)
        #expect(result == .valid)
        #expect(result.isValid)
    }

    @Test("validate rejects wrong extension")
    func validateWrongExtension() {
        let url = URL(fileURLWithPath: "/tmp/not-a-library.app")
        let result = PhotosLibraryPath.validate(url)
        #expect(!result.isValid)
    }

    @Test("validate rejects nonexistent path")
    func validateNonexistent() {
        let url = URL(fileURLWithPath: "/nonexistent/My Photos.photoslibrary")
        let result = PhotosLibraryPath.validate(url)
        #expect(!result.isValid)
    }

    @Test("validate rejects library without database")
    func validateNoDatabase() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).photoslibrary")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = PhotosLibraryPath.validate(tempDir)
        #expect(!result.isValid)
    }
}
