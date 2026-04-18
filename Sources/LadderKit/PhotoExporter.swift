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

    /// Export the requested assets.
    ///
    /// When `localAvailability` is provided, the exporter partitions assets
    /// into a local lane (full `maxConcurrency`) and an iCloud lane. When
    /// `adaptiveController` is also provided, the iCloud lane polls its
    /// ``AdaptiveConcurrencyControlling/currentLimit()`` between dispatches
    /// and reports each outcome via ``AdaptiveConcurrencyControlling/record(_:)``.
    /// Passing both as `nil` preserves 0.4.x behavior.
    public func export(
        uuids: [String],
        localAvailability: LocalAvailabilityProviding? = nil,
        adaptiveController: AdaptiveConcurrencyControlling? = nil
    ) async -> ExportResponse {
        let assets = library.fetchAssets(identifiers: uuids)

        // UUIDs PhotoKit can't find at all → straight to AppleScript fallback
        // (iCloud-only by definition — invisible to PhotoKit fetch).
        let missingUUIDs = uuids.filter { assets[$0] == nil }

        // Partition found assets. Anything not known-local is treated as
        // cloud so a missing availability provider degrades to 0.4.x behavior.
        var localItems: [(String, AssetHandle)] = []
        var cloudItems: [(String, AssetHandle)] = []
        for (uuid, handle) in assets {
            if localAvailability?.isLocallyAvailable(uuid: uuid) == true {
                localItems.append((uuid, handle))
            } else {
                cloudItems.append((uuid, handle))
            }
        }

        async let localExec = runPhotoKitLane(items: localItems, controller: nil)
        async let cloudExec = runPhotoKitLane(items: cloudItems, controller: adaptiveController)

        let localRun = await localExec
        let cloudRun = await cloudExec

        var allResults = localRun.results + cloudRun.results
        var allErrors: [ExportError] = []
        var photoKitFailedUUIDs: [String] = []

        // Shared-album assets that fail PhotoKit go through iCloud's shared-
        // stream pipeline, which the AppleScript path also uses — retrying
        // just waits ~5min for the same server-side error. Short-circuit.
        for pair in localRun.failures + cloudRun.failures {
            if pair.isShared {
                allErrors.append(ExportError(
                    uuid: pair.uuid,
                    message: "Shared-album asset unavailable from iCloud: \(pair.message)",
                    classification: .permanentlyUnavailable
                ))
            } else {
                photoKitFailedUUIDs.append(pair.uuid)
            }
        }

        let fallbackUUIDs = missingUUIDs + photoKitFailedUUIDs
        if !fallbackUUIDs.isEmpty {
            let fb = await exportViaAppleScript(
                uuids: fallbackUUIDs,
                controller: adaptiveController
            )
            allResults.append(contentsOf: fb.results)
            allErrors.append(contentsOf: fb.errors)
        }

        return ExportResponse(results: allResults, errors: allErrors)
    }

    /// Run a PhotoKit export over `items` with bounded, optionally adaptive
    /// concurrency. When `controller` is non-nil, each completion polls
    /// `currentLimit()` and records the outcome.
    private func runPhotoKitLane(
        items: [(String, AssetHandle)],
        controller: AdaptiveConcurrencyControlling?
    ) async -> (results: [ExportResult], failures: [ExportErrorPair]) {
        if items.isEmpty { return ([], []) }

        return await withTaskGroup(
            of: Result<ExportResult, ExportErrorPair>.self
        ) { group in
            var iterator = items.makeIterator()
            var inflight = 0

            // Seed up to the current limit.
            var limit = await self.effectiveLimit(controller)
            while inflight < limit, let (uuid, handle) = iterator.next() {
                group.addTask { await self.exportAsset(uuid: uuid, handle: handle) }
                inflight += 1
            }

            var results: [ExportResult] = []
            var failures: [ExportErrorPair] = []

            for await result in group {
                inflight -= 1

                switch result {
                case .success(let ok):
                    results.append(ok)
                    await controller?.record(.success)
                case .failure(let pair):
                    failures.append(pair)
                    await controller?.record(pair.isShared ? .permanentFailure : .transientFailure)
                }

                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                // Re-poll — the controller may have adjusted between tasks.
                limit = await self.effectiveLimit(controller)
                while inflight < limit, let (uuid, handle) = iterator.next() {
                    group.addTask { await self.exportAsset(uuid: uuid, handle: handle) }
                    inflight += 1
                }
            }

            return (results, failures)
        }
    }

    private func effectiveLimit(
        _ controller: AdaptiveConcurrencyControlling?
    ) async -> Int {
        guard let controller else { return maxConcurrency }
        let limit = await controller.currentLimit()
        return max(1, min(maxConcurrency, limit))
    }

    /// AppleScript fallback, gated the same way as the PhotoKit iCloud lane.
    /// All failures here are iCloud-related by construction — classify as
    /// ``ExportClassification/transientCloud``.
    private func exportViaAppleScript(
        uuids: [String],
        controller: AdaptiveConcurrencyControlling?
    ) async -> (results: [ExportResult], errors: [ExportError]) {
        guard let scriptExporter else {
            let errors = uuids.map {
                ExportError(uuid: $0, message: "Asset not found in Photos library")
            }
            return ([], errors)
        }

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

        return await withTaskGroup(
            of: Result<ExportResult, ScriptFailure>.self
        ) { group in
            var iterator = uuids.makeIterator()
            var inflight = 0

            var limit = await self.effectiveLimit(controller)
            while inflight < limit, let uuid = iterator.next() {
                group.addTask {
                    await self.scriptExportAsset(uuid: uuid, scriptExporter: scriptExporter)
                }
                inflight += 1
            }

            var results: [ExportResult] = []
            var errors: [ExportError] = []

            for await result in group {
                inflight -= 1

                switch result {
                case .success(let ok):
                    results.append(ok)
                    await controller?.record(.success)
                case .failure(let fail):
                    errors.append(ExportError(
                        uuid: fail.uuid,
                        message: fail.message,
                        classification: fail.classification
                    ))
                    await controller?.record(
                        fail.classification == .permanentlyUnavailable
                            ? .permanentFailure : .transientFailure
                    )
                }

                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                limit = await self.effectiveLimit(controller)
                while inflight < limit, let uuid = iterator.next() {
                    group.addTask {
                        await self.scriptExportAsset(uuid: uuid, scriptExporter: scriptExporter)
                    }
                    inflight += 1
                }
            }

            return (results, errors)
        }
    }

    private func scriptExportAsset(
        uuid: String,
        scriptExporter: ScriptExporter
    ) async -> Result<ExportResult, ScriptFailure> {
        do {
            let exportedFile = try await scriptExporter.exportAsset(
                identifier: uuid,
                to: stagingDir,
                timeout: AppleScriptRunner.defaultTimeout
            )

            let sha256 = try FileHasher.sha256(fileAt: exportedFile)
            let attrs = try FileManager.default.attributesOfItem(atPath: exportedFile.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

            let safeDest = try PathSafety.safeDestination(
                stagingDir: stagingDir,
                uuid: uuid,
                originalFilename: exportedFile.lastPathComponent
            )
            try FileManager.default.moveItem(at: exportedFile, to: safeDest)

            let tempSubdir = exportedFile.deletingLastPathComponent()
            if tempSubdir != stagingDir {
                try? FileManager.default.removeItem(at: tempSubdir)
            }

            return .success(ExportResult(
                uuid: uuid,
                path: safeDest.path,
                size: size,
                sha256: sha256
            ))
        } catch let err as AppleScriptError {
            let classification: ExportClassification
            if case .assetUnavailable = err {
                classification = .permanentlyUnavailable
            } else {
                classification = .transientCloud
            }
            return .failure(ScriptFailure(
                uuid: uuid,
                message: err.localizedDescription,
                classification: classification
            ))
        } catch {
            return .failure(ScriptFailure(
                uuid: uuid,
                message: error.localizedDescription,
                classification: .transientCloud
            ))
        }
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
                isShared: handle.isShared
            ))
        }

        FileManager.default.createFile(atPath: destURL.path, contents: nil)

        do {
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
            try? FileManager.default.removeItem(at: destURL)
            return .failure(ExportErrorPair(
                uuid: uuid,
                message: error.localizedDescription,
                isShared: handle.isShared
            ))
        }
    }
}

/// Internal type for passing PhotoKit-lane errors through TaskGroup.
struct ExportErrorPair: Error, Sendable {
    let uuid: String
    let message: String
    let isShared: Bool
}

/// Internal type for passing AppleScript-lane errors through TaskGroup.
private struct ScriptFailure: Error, Sendable {
    let uuid: String
    let message: String
    let classification: ExportClassification
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
