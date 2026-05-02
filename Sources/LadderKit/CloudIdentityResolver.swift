import Foundation
@preconcurrency import Photos

/// Result of resolving a single PhotoKit local identifier to a stable cloud
/// identifier. Maps PhotoKit's `Result<PHCloudIdentifier, Error>` shape onto a
/// stable enum so callers don't need to import `Photos` themselves.
public enum CloudMappingResult: Sendable, Equatable {
    /// A stable cloud identifier — same value for this asset on every device
    /// signed into the same iCloud Photos library.
    case cloud(String)
    /// PhotoKit reports no cloud counterpart for this asset (genuinely local,
    /// never synced, or iCloud Photos disabled). Treat as device-bound.
    case notFound
    /// PhotoKit reports multiple cloud identifiers for this local id (shared
    /// or merged library). Caller must resolve manually; we never silently
    /// pick a winner.
    case multipleFound
    /// Any other error — typically transient. Translation preserves the
    /// localized description so callers can surface it to the user.
    case error(String)
}

/// Abstracts the local→cloud identifier mapping so callers can substitute
/// fakes in tests. Real implementation lives in
/// ``PhotoKitCloudIdentityResolver``.
public protocol CloudIdentityResolving: Sendable {
    /// Resolve a batch of local identifiers (full PhotoKit `"UUID/L0/001"`
    /// form) to cloud identifiers. Always returns one entry per input; no
    /// throws at the function level — per-asset failures surface via
    /// ``CloudMappingResult``.
    func resolve(localIdentifiers: [String]) async -> [String: CloudMappingResult]
}

/// Real `CloudIdentityResolving` backed by `PHPhotoLibrary`. Chunks input
/// into bounded batches, retries `.error` results once after a short delay
/// to absorb the iOS 18.1.1 / Sequoia 15.x async-quirk where the first call
/// returns spurious errors that resolve on a second call.
public struct PhotoKitCloudIdentityResolver: CloudIdentityResolving {
    public let chunkSize: Int
    public let retryDelayNanoseconds: UInt64

    public init(chunkSize: Int = 1000, retryDelayNanoseconds: UInt64 = 500_000_000) {
        self.chunkSize = chunkSize
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    public func resolve(localIdentifiers: [String]) async -> [String: CloudMappingResult] {
        guard !localIdentifiers.isEmpty else { return [:] }

        var combined: [String: CloudMappingResult] = [:]
        combined.reserveCapacity(localIdentifiers.count)

        for chunk in chunks(of: localIdentifiers, size: chunkSize) {
            let raw = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: chunk)
            for (localId, result) in raw {
                combined[localId] = Self.translate(result)
            }
        }

        // Sequoia async-quirk: retry .error entries once.
        let errored = combined.compactMap { (key, value) -> String? in
            if case .error = value { return key } else { return nil }
        }
        if !errored.isEmpty {
            try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            for chunk in chunks(of: errored, size: chunkSize) {
                let raw = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: chunk)
                for (localId, result) in raw {
                    let translated = Self.translate(result)
                    if case .error = translated { continue }
                    combined[localId] = translated
                }
            }
        }

        return combined
    }

    static func translate(_ result: Result<PHCloudIdentifier, Error>) -> CloudMappingResult {
        switch result {
        case .success(let cid):
            return .cloud(cid.stringValue)
        case .failure(let error):
            if let phErr = error as? PHPhotosError {
                switch phErr.code {
                case .identifierNotFound:
                    return .notFound
                case .multipleIdentifiersFound:
                    return .multipleFound
                default:
                    return .error(phErr.localizedDescription)
                }
            }
            return .error(error.localizedDescription)
        }
    }
}

private func chunks<T>(of array: [T], size: Int) -> [[T]] {
    guard size > 0, !array.isEmpty else { return array.isEmpty ? [] : [array] }
    var result: [[T]] = []
    var i = 0
    while i < array.count {
        let end = Swift.min(i + size, array.count)
        result.append(Array(array[i..<end]))
        i = end
    }
    return result
}
