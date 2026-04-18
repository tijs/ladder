import Foundation

/// Tells the exporter whether an asset's original bytes are on disk right now
/// (vs. needing an iCloud download).
///
/// Implementations should be cheap and side-effect free — the exporter calls
/// this synchronously while partitioning a batch.
public protocol LocalAvailabilityProviding: Sendable {
    /// Returns `true` if the asset's original resource is locally cached.
    /// Returns `false` if unknown or iCloud-only.
    func isLocallyAvailable(uuid: String) -> Bool
}

/// A `LocalAvailabilityProviding` backed by a precomputed set of UUIDs.
///
/// Typical use: call ``PhotosDatabase/localAvailableUUIDs(dbPath:)`` once at
/// the start of a backup run and wrap the result.
public struct PhotosDatabaseLocalAvailability: LocalAvailabilityProviding {
    public let localUUIDs: Set<String>

    public init(localUUIDs: Set<String>) {
        self.localUUIDs = localUUIDs
    }

    public func isLocallyAvailable(uuid: String) -> Bool {
        localUUIDs.contains(uuid)
    }

    /// Convenience: load availability directly from a Photos library bundle.
    /// Returns `nil` if the library's `Photos.sqlite` can't be located.
    public static func fromLibrary(at libraryURL: URL) -> PhotosDatabaseLocalAvailability? {
        guard let dbPath = PhotosLibraryPath.databasePath(for: libraryURL) else {
            return nil
        }
        return PhotosDatabaseLocalAvailability(
            localUUIDs: PhotosDatabase.localAvailableUUIDs(dbPath: dbPath)
        )
    }
}
