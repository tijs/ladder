import Foundation
@preconcurrency import Photos

/// Abstraction over PhotoKit for testability.
public protocol PhotoLibrary: Sendable {
    /// Fetch assets by their local identifiers (for export).
    func fetchAssets(identifiers: [String]) -> [String: AssetHandle]

    /// Return the total number of non-trashed assets in the library.
    func totalAssetCount() -> Int

    /// Enumerate all non-trashed assets with core metadata from PhotoKit.
    ///
    /// Returns assets sorted by creation date (newest first).
    /// Enrichment fields (keywords, people, descriptions, albums, edits)
    /// are populated separately via ``PhotosDatabase``.
    func enumerateAssets() -> [AssetInfo]
}

/// Abstraction over a single asset's exportable resource.
public protocol AssetHandle: Sendable {
    var originalFilename: String { get }
    var resourceType: PHAssetResourceType { get }
    /// True for iCloud Shared Album assets (`PHAsset.sourceType == .typeCloudShared`).
    /// These go through a different iCloud pipeline that can fail server-side
    /// with no recoverable fallback, so callers should skip retry paths on failure.
    var isShared: Bool { get }

    /// Write the asset's original data to a file, streaming chunks to the handler.
    /// Each chunk is delivered to `chunkHandler` before being written, enabling
    /// inline hashing. The file at `destinationURL` contains the complete data on success.
    func writeData(
        to destinationURL: URL,
        networkAccessAllowed: Bool,
        chunkHandler: @escaping @Sendable (Data) -> Void
    ) async throws -> Int64
}

/// Real PhotoKit implementation.
public struct PhotoKitLibrary: PhotoLibrary, @unchecked Sendable {
    public init() {}

    /// Enumerate all non-trashed assets and enrich them from Photos.sqlite
    /// (filenames, albums, keywords, people, descriptions, edits). If the
    /// library's database can't be located, returns the un-enriched list.
    public static func loadEnrichedAssets(libraryURL: URL) -> [AssetInfo] {
        var assets = PhotoKitLibrary().enumerateAssets()
        if let dbPath = PhotosLibraryPath.databasePath(for: libraryURL) {
            let enrichment = PhotosDatabase.readEnrichment(dbPath: dbPath)
            PhotosDatabase.enrich(&assets, with: enrichment)
        }
        return assets
    }

    public func fetchAssets(identifiers: [String]) -> [String: AssetHandle] {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: identifiers,
            options: nil
        )

        // PhotoKit returns assets keyed by their full localIdentifier
        // ("UUID/L0/001"). Callers may pass bare UUIDs or full identifiers;
        // match each fetched asset back to the caller's input string so the
        // returned dict is keyed by whatever the caller asked for.
        var result: [String: AssetHandle] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            guard let resource = resources.first(where: { $0.type == .photo || $0.type == .video })
                ?? resources.first
            else { return }
            let key = identifiers.first(where: { id in
                asset.localIdentifier == id || asset.localIdentifier.hasPrefix(id + "/")
            }) ?? asset.localIdentifier
            result[key] = PhotoKitAssetHandle(
                resource: resource,
                isShared: asset.sourceType == .typeCloudShared,
            )
        }
        return result
    }

    public func totalAssetCount() -> Int {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
        let result = PHAsset.fetchAssets(with: options)
        return result.count
    }

    public func enumerateAssets() -> [AssetInfo] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: options)
        var assets: [AssetInfo] = []
        assets.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { phAsset, _, _ in
            let kind: AssetKind = phAsset.mediaType == .video ? .video : .photo

            let info = AssetInfo(
                identifier: phAsset.localIdentifier,
                creationDate: phAsset.creationDate,
                kind: kind,
                pixelWidth: phAsset.pixelWidth,
                pixelHeight: phAsset.pixelHeight,
                latitude: phAsset.location?.coordinate.latitude,
                longitude: phAsset.location?.coordinate.longitude,
                isFavorite: phAsset.isFavorite
            )
            assets.append(info)
        }

        return assets
    }
}

struct PhotoKitAssetHandle: AssetHandle {
    let resource: PHAssetResource
    let isShared: Bool

    var originalFilename: String { resource.originalFilename }
    var resourceType: PHAssetResourceType { resource.type }

    func writeData(
        to destinationURL: URL,
        networkAccessAllowed: Bool,
        chunkHandler: @escaping @Sendable (Data) -> Void
    ) async throws -> Int64 {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = networkAccessAllowed

        let handle = try FileHandle(forWritingTo: destinationURL)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    chunkHandler(data)
                    do {
                        try handle.write(contentsOf: data)
                    } catch {
                        // Error will surface via the file size mismatch or next write
                    }
                },
                completionHandler: { error in
                    try? handle.close()
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }
}
