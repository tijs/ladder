import Foundation
@preconcurrency import Photos

/// Abstraction over PhotoKit for testability.
public protocol PhotoLibrary: Sendable {
    /// Fetch assets by their local identifiers (for export).
    func fetchAssets(identifiers: [String]) -> [String: AssetHandle]

    /// Return the total number of non-trashed assets in the library.
    func totalAssetCount() -> Int

    /// Enumerate all non-trashed assets with their metadata.
    ///
    /// Returns assets sorted by creation date (newest first).
    /// Each asset includes album membership and edit detection.
    func enumerateAssets() -> [AssetInfo]
}

/// Abstraction over a single asset's exportable resource.
public protocol AssetHandle: Sendable {
    var originalFilename: String { get }
    var resourceType: PHAssetResourceType { get }

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
            result[asset.localIdentifier] = PhotoKitAssetHandle(resource: resource)
        }
        return result
    }

    public func totalAssetCount() -> Int {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        let result = PHAsset.fetchAssets(with: options)
        return result.count
    }

    public func enumerateAssets() -> [AssetInfo] {
        let albumMap = buildAlbumMap()

        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: options)
        var assets: [AssetInfo] = []
        assets.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { phAsset, _, _ in
            let info = self.assetInfo(from: phAsset, albumMap: albumMap)
            assets.append(info)
        }

        return assets
    }

    // MARK: - Private

    private func assetInfo(
        from phAsset: PHAsset,
        albumMap: [String: [AlbumInfo]]
    ) -> AssetInfo {
        let resources = PHAssetResource.assetResources(for: phAsset)
        let primaryResource = resources.first(where: { $0.type == .photo || $0.type == .video })
            ?? resources.first

        let hasEdit = resources.contains { $0.type == .adjustmentData }
            && resources.contains {
                $0.type == .fullSizePhoto || $0.type == .fullSizeVideo
            }

        let kind: AssetKind = phAsset.mediaType == .video ? .video : .photo

        return AssetInfo(
            identifier: phAsset.localIdentifier,
            creationDate: phAsset.creationDate,
            kind: kind,
            pixelWidth: phAsset.pixelWidth,
            pixelHeight: phAsset.pixelHeight,
            latitude: phAsset.location?.coordinate.latitude,
            longitude: phAsset.location?.coordinate.longitude,
            isFavorite: phAsset.isFavorite,
            originalFilename: primaryResource?.originalFilename,
            uniformTypeIdentifier: primaryResource?.uniformTypeIdentifier,
            hasEdit: hasEdit,
            albums: albumMap[phAsset.localIdentifier] ?? []
        )
    }

    /// Build a map of asset identifier → albums it belongs to.
    ///
    /// Fetches all user-created albums and smart albums, then for each album
    /// fetches its assets and records the membership.
    private func buildAlbumMap() -> [String: [AlbumInfo]] {
        var map: [String: [AlbumInfo]] = [:]

        let albumTypes: [(PHAssetCollectionType, PHAssetCollectionSubtype)] = [
            (.album, .any),
            (.smartAlbum, .any),
        ]

        for (type, subtype) in albumTypes {
            let collections = PHAssetCollection.fetchAssetCollections(
                with: type,
                subtype: subtype,
                options: nil
            )

            collections.enumerateObjects { collection, _, _ in
                guard let title = collection.localizedTitle else { return }

                let albumInfo = AlbumInfo(
                    identifier: collection.localIdentifier,
                    title: title
                )

                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                assets.enumerateObjects { asset, _, _ in
                    map[asset.localIdentifier, default: []].append(albumInfo)
                }
            }
        }

        return map
    }
}

struct PhotoKitAssetHandle: AssetHandle {
    let resource: PHAssetResource

    var originalFilename: String { resource.originalFilename }
    var resourceType: PHAssetResourceType { resource.type }

    func writeData(
        to destinationURL: URL,
        networkAccessAllowed: Bool,
        chunkHandler: @escaping @Sendable (Data) -> Void
    ) async throws -> Int64 {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = networkAccessAllowed

        // Use requestData to stream chunks — enables inline hashing while writing
        let handle = try FileHandle(forWritingTo: destinationURL)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    chunkHandler(data)
                    handle.write(data)
                },
                completionHandler: { error in
                    handle.closeFile()
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
