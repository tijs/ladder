import Foundation

public final class PhotoExporter: Sendable {
    private let stagingDir: URL
    private let library: PhotoLibrary
    private let scriptExporter: ScriptExporter?
    private let maxConcurrency: Int

    public init(
        stagingDir: URL,
        library: PhotoLibrary = PhotoKitLibrary(),
        scriptExporter: ScriptExporter? = nil,
        maxConcurrency: Int = 6
    ) {
        self.stagingDir = stagingDir
        self.library = library
        self.scriptExporter = scriptExporter
        self.maxConcurrency = maxConcurrency
    }

    /// Pre-flight check: verify Automation permission if a script exporter is configured.
    /// Call before `export()` to fail fast with a clear error instead of mid-backup.
    public func checkPermissions() async throws {
        try await scriptExporter?.checkPermissions()
    }

    public func export(uuids: [String]) async -> ExportResponse {
        let assets = library.fetchAssets(identifiers: uuids)

        // Identify missing UUIDs (PhotoKit can't find them)
        let missingUUIDs = uuids.filter { assets[$0] == nil }

        // Export found assets with bounded concurrency (unchanged)
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
        var allErrors: [ExportError] = []
        var photoKitFailedUUIDs: [String] = []
        // Shared-album assets that fail PhotoKit go through iCloud's shared-stream
        // pipeline, which the AppleScript path also uses — retrying via AppleScript
        // just waits ~5min for the same server-side error. Short-circuit these.
        for result in exportResults {
            switch result {
            case .success(let exportResult):
                allResults.append(exportResult)
            case .failure(let pair):
                if pair.isShared {
                    allErrors.append(ExportError(
                        uuid: pair.uuid,
                        message: "Shared-album asset unavailable from iCloud: \(pair.message)",
                        unavailable: true,
                    ))
                } else {
                    photoKitFailedUUIDs.append(pair.uuid)
                }
            }
        }

        // AppleScript fallback for:
        // 1. UUIDs that PhotoKit couldn't find at all (iCloud-only, invisible to fetchAssets)
        // 2. UUIDs that PhotoKit found but failed to export (e.g. iCloud download errors)
        let fallbackUUIDs = missingUUIDs + photoKitFailedUUIDs
        if !fallbackUUIDs.isEmpty {
            let (fallbackResults, fallbackErrors) = await exportViaAppleScript(uuids: fallbackUUIDs)
            allResults.append(contentsOf: fallbackResults)
            allErrors.append(contentsOf: fallbackErrors)
        }

        return ExportResponse(results: allResults, errors: allErrors)
    }

    /// Attempt AppleScript fallback for UUIDs that PhotoKit couldn't find.
    private func exportViaAppleScript(
        uuids: [String]
    ) async -> ([ExportResult], [ExportError]) {
        guard let scriptExporter else {
            // No script exporter: report all as "not found" (original behavior)
            let errors = uuids.map { ExportError(uuid: $0, message: "Asset not found in Photos library") }
            return ([], errors)
        }

        // Check disk space before starting iCloud downloads
        let freeSpace = availableDiskSpace(at: stagingDir)
        if freeSpace < AppleScriptRunner.minimumFreeSpace {
            let gbFree = Double(freeSpace) / 1_073_741_824
            let errors = uuids.map { uuid in
                ExportError(
                    uuid: uuid,
                    message: String(
                        format: "Skipped iCloud download: only %.1f GB free (need 2 GB)",
                        gbFree
                    )
                )
            }
            return ([], errors)
        }

        var results: [ExportResult] = []
        var errors: [ExportError] = []

        for uuid in uuids {
            if Task.isCancelled { break }

            do {
                let exportedFile = try await scriptExporter.exportAsset(
                    identifier: uuid,
                    to: stagingDir,
                    timeout: AppleScriptRunner.defaultTimeout
                )

                let sha256 = try FileHasher.sha256(fileAt: exportedFile)
                let attrs = try FileManager.default.attributesOfItem(atPath: exportedFile.path)
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

                // Move from temp subdirectory to staging dir with safe naming
                let safeDest = try PathSafety.safeDestination(
                    stagingDir: stagingDir,
                    uuid: uuid,
                    originalFilename: exportedFile.lastPathComponent
                )
                try FileManager.default.moveItem(at: exportedFile, to: safeDest)

                // Clean up the per-asset temp subdirectory
                let tempSubdir = exportedFile.deletingLastPathComponent()
                if tempSubdir != stagingDir {
                    try? FileManager.default.removeItem(at: tempSubdir)
                }

                results.append(ExportResult(
                    uuid: uuid,
                    path: safeDest.path,
                    size: size,
                    sha256: sha256
                ))
            } catch {
                errors.append(ExportError(
                    uuid: uuid,
                    message: error.localizedDescription
                ))
            }
        }

        return (results, errors)
    }

    private func exportAsset(
        uuid: String,
        handle: AssetHandle
    ) async -> Result<ExportResult, ExportErrorPair> {
        let destURL: URL
        do {
            destURL = try PathSafety.safeDestination(
                stagingDir: stagingDir,
                uuid: uuid,
                originalFilename: handle.originalFilename
            )
        } catch {
            return .failure(ExportErrorPair(
                uuid: uuid,
                message: error.localizedDescription,
                isShared: handle.isShared,
            ))
        }

        // Create empty file for writing
        FileManager.default.createFile(atPath: destURL.path, contents: nil)

        do {
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
            // Clean up the empty/partial file so AppleScript fallback can reuse the path
            try? FileManager.default.removeItem(at: destURL)
            return .failure(ExportErrorPair(
                uuid: uuid,
                message: error.localizedDescription,
                isShared: handle.isShared,
            ))
        }
    }
}

/// Internal type for passing errors through TaskGroup.
struct ExportErrorPair: Error, Sendable {
    let uuid: String
    let message: String
    let isShared: Bool
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
