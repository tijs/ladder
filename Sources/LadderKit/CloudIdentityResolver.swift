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
    public typealias MappingSource = @Sendable ([String]) -> [String: CloudMappingResult]
    public typealias AuthorizationSource = @Sendable () async -> PHAuthorizationStatus

    public let chunkSize: Int
    public let retryDelayNanoseconds: UInt64
    private let mappingSource: MappingSource
    private let authorizationSource: AuthorizationSource

    public init(chunkSize: Int = 1000, retryDelayNanoseconds: UInt64 = 500_000_000) {
        self.init(
            chunkSize: chunkSize,
            retryDelayNanoseconds: retryDelayNanoseconds,
            mappingSource: { ids in
                let raw = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: ids)
                var translated: [String: CloudMappingResult] = [:]
                translated.reserveCapacity(raw.count)
                for (id, result) in raw {
                    translated[id] = PhotoKitCloudIdentityResolver.translate(result)
                }
                return translated
            },
            authorizationSource: {
                await PhotoKitCloudIdentityResolver.requestReadWriteAuthorization()
            },
        )
    }

    /// Test-friendly initializer that injects the underlying PhotoKit calls.
    /// Production code should use the no-arg form.
    public init(
        chunkSize: Int,
        retryDelayNanoseconds: UInt64,
        mappingSource: @escaping MappingSource,
        authorizationSource: @escaping AuthorizationSource,
    ) {
        self.chunkSize = chunkSize
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.mappingSource = mappingSource
        self.authorizationSource = authorizationSource
    }

    public func resolve(localIdentifiers: [String]) async -> [String: CloudMappingResult] {
        guard !localIdentifiers.isEmpty else { return [:] }

        // PhotoKit requires .readWrite for cloudIdentifierMappings —
        // .readOnly silently returns an empty dict on first call. Request
        // up-front so the consent dialog (if any) fires before the resolve
        // path. Already-determined statuses short-circuit cheaply.
        let status = await authorizationSource()
        guard status == .authorized || status == .limited else {
            // Surface every input as .error so callers can decide how to
            // present the failure (the migration runner aborts on a 100%
            // unresolved batch by default).
            var denied: [String: CloudMappingResult] = [:]
            denied.reserveCapacity(localIdentifiers.count)
            let message = "PhotoKit access not granted (status=\(status.rawValue))"
            for id in localIdentifiers { denied[id] = .error(message) }
            return denied
        }

        var combined: [String: CloudMappingResult] = [:]
        combined.reserveCapacity(localIdentifiers.count)

        for chunk in chunks(of: localIdentifiers, size: chunkSize) {
            for (localId, result) in mappingSource(chunk) {
                combined[localId] = result
            }
        }

        // Sequoia async-quirk: retry .error entries up to 2 times with
        // exponential backoff. Persistent errors after both retries remain
        // as .error so callers can surface them — silently downgrading to
        // .notFound would mis-classify transient PhotoKit failures as
        // "asset has no cloud counterpart" and lock the entry into the
        // local fallback path forever.
        for attempt in 0..<2 {
            let errored = combined.compactMap { (key, value) -> String? in
                if case .error = value { return key } else { return nil }
            }
            if errored.isEmpty { break }

            let delay = retryDelayNanoseconds * UInt64(1 << attempt)
            try? await Task.sleep(nanoseconds: delay)

            for chunk in chunks(of: errored, size: chunkSize) {
                for (localId, result) in mappingSource(chunk) {
                    // Only overwrite on success/known-status — persistent
                    // .error must not stomp on a prior attempt's message.
                    if case .error = result {
                        if attempt == 1 { combined[localId] = result }
                        continue
                    }
                    combined[localId] = result
                }
            }
        }

        return combined
    }

    /// Wrap PhotoKit's callback-based authorization request as async.
    /// Idempotent — subsequent calls return the existing status without
    /// re-prompting.
    static func requestReadWriteAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
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
