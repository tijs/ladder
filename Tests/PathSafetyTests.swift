import Foundation
import Testing

@testable import LadderKit

@Suite("PathSafety")
struct PathSafetyTests {
    @Test("sanitizeFilename replaces path separators")
    func sanitizeSlashes() {
        let result = PathSafety.sanitizeFilename("B84E8479-475C/L0/001")
        #expect(!result.contains("/"))
        #expect(result == "B84E8479-475C_L0_001")
    }

    @Test("sanitizeFilename handles clean filenames")
    func sanitizeClean() {
        let result = PathSafety.sanitizeFilename("IMG_0001.HEIC")
        #expect(result == "IMG_0001.HEIC")
    }

    @Test("safeDestination produces valid path inside staging dir")
    func safeDestinationValid() throws {
        let staging = URL(fileURLWithPath: "/tmp/staging")
        let dest = try PathSafety.safeDestination(
            stagingDir: staging,
            uuid: "abc-123",
            originalFilename: "IMG_0001.HEIC"
        )
        #expect(dest.path.hasPrefix("/tmp/staging/"))
        #expect(dest.lastPathComponent == "abc-123_IMG_0001.HEIC")
    }

    @Test("safeDestination sanitizes PHAsset-style identifiers with slashes")
    func safeDestinationWithSlashes() throws {
        let staging = URL(fileURLWithPath: "/tmp/staging")
        let dest = try PathSafety.safeDestination(
            stagingDir: staging,
            uuid: "B84E8479-475C-4727/L0/001",
            originalFilename: "IMG_0001.HEIC"
        )
        #expect(dest.path.hasPrefix("/tmp/staging/"))
        #expect(!dest.lastPathComponent.contains("/"))
    }

    @Test("safeDestination sanitizes traversal in filename")
    func safeDestinationTraversal() throws {
        let staging = URL(fileURLWithPath: "/tmp/staging")
        let dest = try PathSafety.safeDestination(
            stagingDir: staging,
            uuid: "uuid-1",
            originalFilename: "../../../etc/passwd"
        )
        // Slashes replaced, file stays inside staging dir
        #expect(dest.path.hasPrefix("/tmp/staging/"))
        #expect(!dest.lastPathComponent.contains("/"))
    }

    @Test("validateStagingDir rejects empty path")
    func validateEmpty() {
        #expect(throws: ExportFailure.self) {
            _ = try PathSafety.validateStagingDir("")
        }
    }

    @Test("validateStagingDir rejects relative path")
    func validateRelative() {
        #expect(throws: ExportFailure.self) {
            _ = try PathSafety.validateStagingDir("relative/path")
        }
    }

    @Test("validateStagingDir rejects system paths")
    func validateSystem() {
        #expect(throws: ExportFailure.self) {
            _ = try PathSafety.validateStagingDir("/System/Library")
        }
    }

    @Test("validateStagingDir accepts valid path")
    func validateValid() throws {
        let url = try PathSafety.validateStagingDir("/tmp/test-staging")
        #expect(url.path == "/tmp/test-staging")
    }
}
