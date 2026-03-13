import Foundation

/// Input: a request to export specific assets by UUID.
public struct ExportRequest: Codable, Sendable {
    public let uuids: [String]
    public let stagingDir: String

    public init(uuids: [String], stagingDir: String) {
        self.uuids = uuids
        self.stagingDir = stagingDir
    }
}

/// Output: result for a single exported asset.
public struct ExportResult: Codable, Sendable {
    public let uuid: String
    public let path: String
    public let size: Int64
    public let sha256: String

    public init(uuid: String, path: String, size: Int64, sha256: String) {
        self.uuid = uuid
        self.path = path
        self.size = size
        self.sha256 = sha256
    }
}

/// Output: the full response written to stdout.
public struct ExportResponse: Codable, Sendable {
    public let results: [ExportResult]
    public let errors: [ExportError]

    public init(results: [ExportResult], errors: [ExportError]) {
        self.results = results
        self.errors = errors
    }
}

public struct ExportError: Codable, Sendable {
    public let uuid: String
    public let message: String

    public init(uuid: String, message: String) {
        self.uuid = uuid
        self.message = message
    }
}
