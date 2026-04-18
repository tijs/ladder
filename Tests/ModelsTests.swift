import Foundation
import Testing

@testable import LadderKit

@Suite("Models")
struct ModelsTests {
    @Test("ExportRequest round-trips through JSON")
    func exportRequestRoundTrip() throws {
        let request = ExportRequest(
            uuids: ["uuid-1", "uuid-2"],
            stagingDir: "/tmp/staging"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ExportRequest.self, from: data)

        #expect(decoded.uuids == ["uuid-1", "uuid-2"])
        #expect(decoded.stagingDir == "/tmp/staging")
    }

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
    }

    @Test("ExportError decodes legacy payload without classification")
    func exportErrorLegacyDecode() throws {
        let json = #"{"uuid":"u1","message":"boom","unavailable":true}"#
        let err = try JSONDecoder().decode(ExportError.self, from: Data(json.utf8))
        #expect(err.unavailable == true)
        #expect(err.classification == .permanentlyUnavailable)
    }

    @Test("ExportError decodes legacy payload without unavailable or classification")
    func exportErrorLegacyDecodeMinimal() throws {
        let json = #"{"uuid":"u1","message":"boom"}"#
        let err = try JSONDecoder().decode(ExportError.self, from: Data(json.utf8))
        #expect(err.unavailable == false)
        #expect(err.classification == .other)
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
        #expect(decoded.unavailable == false)
    }

    @Test("ExportError with permanentlyUnavailable sets legacy unavailable flag")
    func exportErrorPermanentlyUnavailable() throws {
        let err = ExportError(uuid: "u1", message: "gone", classification: .permanentlyUnavailable)
        #expect(err.unavailable == true)
        let data = try JSONEncoder().encode(err)
        let decoded = try JSONDecoder().decode(ExportError.self, from: data)
        #expect(decoded.classification == .permanentlyUnavailable)
        #expect(decoded.unavailable == true)
    }

    @Test("ExportRequest decodes from expected JSON format")
    func exportRequestFromJSON() throws {
        let json = """
            {"uuids":["abc","def"],"stagingDir":"/tmp/test"}
            """
        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(ExportRequest.self, from: data)

        #expect(request.uuids == ["abc", "def"])
        #expect(request.stagingDir == "/tmp/test")
    }
}
