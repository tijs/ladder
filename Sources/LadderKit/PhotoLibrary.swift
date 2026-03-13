import Foundation
@preconcurrency import Photos

/// Abstraction over PhotoKit for testability.
public protocol PhotoLibrary: Sendable {
    /// Fetch assets by their local identifiers.
    func fetchAssets(identifiers: [String]) -> [String: AssetHandle]
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
public struct PhotoKitLibrary: PhotoLibrary {
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
