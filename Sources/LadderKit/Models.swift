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

/// Classifies the nature of an export failure so callers can route it to the
/// right retry/skip policy.
public enum ExportClassification: String, Codable, Sendable {
    /// Unclassified / generic failure (default for legacy payloads).
    case other
    /// iCloud download failed transiently — retrying later is reasonable.
    /// Examples: throttling, network glitch, pending server-side processing,
    /// AppleScript export returning success-with-no-file.
    case transientCloud
    /// Asset's bytes cannot be retrieved from iCloud (e.g. a shared-album
    /// asset whose owner's derivative is unreachable). Retries are pointless.
    case permanentlyUnavailable
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
    /// The asset cannot be downloaded from iCloud and retries are pointless.
    ///
    /// Retained for backward compatibility. New callers should prefer
    /// ``classification`` and treat `unavailable == true` as equivalent to
    /// ``ExportClassification/permanentlyUnavailable``.
    public let unavailable: Bool
    /// Structured classification of the failure. Defaults to ``ExportClassification/other``
    /// when decoding legacy payloads that predate this field; derived from
    /// ``unavailable`` when that flag is set on a legacy payload.
    public let classification: ExportClassification

    public init(
        uuid: String,
        message: String,
        classification: ExportClassification = .other
    ) {
        self.uuid = uuid
        self.message = message
        self.classification = classification
        self.unavailable = (classification == .permanentlyUnavailable)
    }

    private enum CodingKeys: String, CodingKey {
        case uuid, message, unavailable, classification
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try c.decode(String.self, forKey: .uuid)
        message = try c.decode(String.self, forKey: .message)
        let legacyUnavailable = try c.decodeIfPresent(Bool.self, forKey: .unavailable) ?? false
        if let decoded = try c.decodeIfPresent(ExportClassification.self, forKey: .classification) {
            classification = decoded
        } else {
            classification = legacyUnavailable ? .permanentlyUnavailable : .other
        }
        unavailable = (classification == .permanentlyUnavailable)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uuid, forKey: .uuid)
        try c.encode(message, forKey: .message)
        try c.encode(unavailable, forKey: .unavailable)
        try c.encode(classification, forKey: .classification)
    }
}
