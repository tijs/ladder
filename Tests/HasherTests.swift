import Foundation
import Testing

@testable import LadderKit

@Suite("FileHasher")
struct HasherTests {
    @Test("SHA-256 of known content")
    func sha256KnownContent() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("hasher-test-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // "hello\n" has a well-known SHA-256
        try Data("hello\n".utf8).write(to: fileURL)

        let hash = try FileHasher.sha256(fileAt: fileURL)

        // sha256("hello\n") = 5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03
        #expect(hash == "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03")
    }

    @Test("SHA-256 of empty file")
    func sha256EmptyFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("hasher-test-empty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try Data().write(to: fileURL)

        let hash = try FileHasher.sha256(fileAt: fileURL)

        // sha256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("SHA-256 throws for missing file")
    func sha256MissingFile() {
        let bogusURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)")

        #expect(throws: (any Error).self) {
            try FileHasher.sha256(fileAt: bogusURL)
        }
    }
}
