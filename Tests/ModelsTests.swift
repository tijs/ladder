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
