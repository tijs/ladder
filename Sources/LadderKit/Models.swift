import Foundation

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

    /// Returns a copy with `uuid` replaced. Use when an upstream caller
    /// fetches by one identity (e.g. PhotoKit local UUID) but needs to
    /// publish the result under another (e.g. `PHCloudIdentifier`). Keeping
    /// this as a method on the type guarantees future fields are preserved
    /// without each caller having to update its own struct-rebuild
    /// boilerplate.
    public func withUUID(_ newUUID: String) -> ExportResult {
        ExportResult(uuid: newUUID, path: path, size: size, sha256: sha256)
    }
}

/// Classifies the nature of an export failure so callers can route it to the
/// right retry/skip policy.
public enum ExportClassification: String, Codable, Sendable {
    /// Unclassified / generic failure.
    case other
    /// iCloud download failed transiently — retrying later is reasonable.
    /// Examples: throttling, network glitch, pending server-side processing,
    /// AppleScript export returning success-with-no-file.
    case transientCloud
    /// Asset's bytes cannot be retrieved from iCloud (e.g. a shared-album
    /// asset whose owner's derivative is unreachable). Retries are pointless.
    case permanentlyUnavailable
}

/// Output: the full response from an export batch.
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
    public let classification: ExportClassification

    public init(
        uuid: String,
        message: String,
        classification: ExportClassification = .other
    ) {
        self.uuid = uuid
        self.message = message
        self.classification = classification
    }

    /// Returns a copy with `uuid` replaced, preserving `message` and
    /// `classification` (and the derived `unavailable` legacy flag). Same
    /// rationale as ``ExportResult/withUUID(_:)`` — keeps identity
    /// re-mapping at the call site free of struct-rebuild boilerplate.
    public func withUUID(_ newUUID: String) -> ExportError {
        ExportError(uuid: newUUID, message: message, classification: classification)
    }
}
