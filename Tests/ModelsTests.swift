import Foundation
import Testing

@testable import LadderKit

@Suite("Models")
struct ModelsTests {
    @Test("ExportResponse round-trips through JSON")
    func exportResponseRoundTrip() throws {
        let response = ExportResponse(
            results: [
                ExportResult(
                    uuid: "uuid-1",
                    path: "/tmp/staging/uuid-1_IMG_001.HEIC",
                    size: 3_158_112,
                    sha256: "abc123"
                )
            ],
            errors: [
                ExportError(uuid: "uuid-2", message: "Not found")
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(response)
        let decoded = try JSONDecoder().decode(ExportResponse.self, from: data)

        #expect(decoded.results.count == 1)
        #expect(decoded.results[0].uuid == "uuid-1")
        #expect(decoded.results[0].size == 3_158_112)
        #expect(decoded.errors.count == 1)
        #expect(decoded.errors[0].message == "Not found")
        #expect(decoded.errors[0].classification == .other)
    }

    @Test("ExportError round-trips with classification")
    func exportErrorRoundTripWithClassification() throws {
        let original = ExportError(
            uuid: "u1",
            message: "transient",
            classification: .transientCloud
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExportError.self, from: data)
        #expect(decoded.classification == .transientCloud)
    }

    @Test("ExportResult.withUUID swaps uuid and preserves all other fields")
    func exportResultWithUUID() {
        let original = ExportResult(
            uuid: "local-1",
            path: "/tmp/staging/local-1_IMG.HEIC",
            size: 12_345,
            sha256: "deadbeef"
        )
        let remapped = original.withUUID("CLOUD-1")
        #expect(remapped.uuid == "CLOUD-1")
        #expect(remapped.path == original.path)
        #expect(remapped.size == original.size)
        #expect(remapped.sha256 == original.sha256)
    }

    @Test("ExportError.withUUID swaps uuid and preserves message + classification")
    func exportErrorWithUUID() {
        let original = ExportError(
            uuid: "local-1",
            message: "transient blip",
            classification: .transientCloud
        )
        let remapped = original.withUUID("CLOUD-1")
        #expect(remapped.uuid == "CLOUD-1")
        #expect(remapped.message == original.message)
        #expect(remapped.classification == .transientCloud)
        #expect(remapped.unavailable == false)
    }

    @Test("ExportError.withUUID preserves permanentlyUnavailable derived flag")
    func exportErrorWithUUIDUnavailable() {
        let original = ExportError(
            uuid: "local-1",
            message: "gone",
            classification: .permanentlyUnavailable
        )
        let remapped = original.withUUID("CLOUD-1")
        #expect(remapped.classification == .permanentlyUnavailable)
        #expect(remapped.unavailable == true)
    }
}
