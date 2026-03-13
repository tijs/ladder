import Foundation

public final class PhotoExporter: Sendable {
    private let stagingDir: URL
    private let library: PhotoLibrary
    private let maxConcurrency: Int

    public init(
        stagingDir: URL,
        library: PhotoLibrary = PhotoKitLibrary(),
        maxConcurrency: Int = 6
    ) {
        self.stagingDir = stagingDir
        self.library = library
        self.maxConcurrency = maxConcurrency
    }

    public func export(uuids: [String]) async -> ExportResponse {
        let assets = library.fetchAssets(identifiers: uuids)

        // Report missing UUIDs
        let errors: [ExportError] = uuids
            .filter { assets[$0] == nil }
            .map { ExportError(uuid: $0, message: "Asset not found in Photos library") }

        // Export found assets with bounded concurrency
        let exportResults = await withTaskGroup(
            of: Result<ExportResult, ExportErrorPair>.self
        ) { group in
            var pending = 0
            var iterator = assets.makeIterator()
            var results: [Result<ExportResult, ExportErrorPair>] = []

            // Seed the group with initial tasks up to maxConcurrency
            while pending < maxConcurrency, let (uuid, handle) = iterator.next() {
                group.addTask { await self.exportAsset(uuid: uuid, handle: handle) }
                pending += 1
            }

            // As each completes, start the next (checking cancellation between assets)
            for await result in group {
                results.append(result)
                if Task.isCancelled { break }
                if let (uuid, handle) = iterator.next() {
                    group.addTask { await self.exportAsset(uuid: uuid, handle: handle) }
                }
            }

            return results
        }

        var allResults: [ExportResult] = []
        var allErrors = errors
        for result in exportResults {
            switch result {
            case .success(let exportResult):
                allResults.append(exportResult)
            case .failure(let pair):
                allErrors.append(ExportError(uuid: pair.uuid, message: pair.message))
            }
        }

        return ExportResponse(results: allResults, errors: allErrors)
    }

    private func exportAsset(
        uuid: String,
        handle: AssetHandle
    ) async -> Result<ExportResult, ExportErrorPair> {
        do {
            let destURL = try PathSafety.safeDestination(
                stagingDir: stagingDir,
                uuid: uuid,
                originalFilename: handle.originalFilename
            )

            // Create empty file for writing
            FileManager.default.createFile(atPath: destURL.path, contents: nil)

            // Stream data: write to file + hash simultaneously
            let hasher = StreamingHasher()
            let size = try await handle.writeData(
                to: destURL,
                networkAccessAllowed: true,
                chunkHandler: { data in hasher.update(data) }
            )
            let sha256 = hasher.finalize()

            return .success(ExportResult(
                uuid: uuid,
                path: destURL.path,
                size: size,
                sha256: sha256
            ))
        } catch {
            return .failure(ExportErrorPair(uuid: uuid, message: error.localizedDescription))
        }
    }
}

/// Internal type for passing errors through TaskGroup.
struct ExportErrorPair: Error, Sendable {
    let uuid: String
    let message: String
}

public enum ExportFailure: LocalizedError {
    case noResource(String)
    case unsafePath(String)
    case invalidStagingDir(String)

    public var errorDescription: String? {
        switch self {
        case .noResource(let uuid):
            return "No exportable resource found for asset \(uuid)"
        case .unsafePath(let uuid):
            return "Destination path escapes staging directory for asset \(uuid)"
        case .invalidStagingDir(let reason):
            return "Invalid staging directory: \(reason)"
        }
    }
}
