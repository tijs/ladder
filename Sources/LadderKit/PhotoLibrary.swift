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

    public func fetchAssets(identifiers: [String]) -> [String: AssetHandle] {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: identifiers,
            options: nil
        )

        var result: [String: AssetHandle] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            guard let resource = resources.first(where: { $0.type == .photo || $0.type == .video })
                ?? resources.first
            else { return }
            result[asset.localIdentifier] = PhotoKitAssetHandle(
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
