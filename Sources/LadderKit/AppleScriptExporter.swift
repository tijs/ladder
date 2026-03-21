import Foundation

/// Abstraction over AppleScript-based export for testability and dual-use (CLI/GUI).
///
/// When PhotoKit can't find an asset (typically iCloud-only with Optimize Storage enabled),
/// the AppleScript fallback asks Photos.app to export it. Photos.app handles the iCloud
/// download transparently.
///
/// Inspired by [osxphotos](https://github.com/RhetTbull/osxphotos) (MIT license).
public protocol ScriptExporter: Sendable {
    /// Verify that required permissions are available before starting exports.
    /// Throws `AppleScriptError.automationPermissionDenied` if not granted.
    func checkPermissions() async throws

    /// Export an asset by its local identifier, writing the original file to `directory`.
    /// Returns the URL of the exported file on success.
    func exportAsset(identifier: String, to directory: URL, timeout: TimeInterval) async throws -> URL
}

/// Export via `osascript` subprocess — works from both CLI and GUI contexts.
public struct AppleScriptRunner: ScriptExporter {
    /// Default timeout per asset (10 minutes).
    public static let defaultTimeout: TimeInterval = 600

    /// Minimum free disk space required before attempting iCloud exports (2 GB).
    public static let minimumFreeSpace: UInt64 = 2 * 1024 * 1024 * 1024

    public init() {}

    /// Run a lightweight AppleScript probe to verify Automation permission.
    public func checkPermissions() async throws {
        let probe = #"tell application "Photos" to return "ok""#
        let result = try await runOsascript(script: probe, timeout: 30)
        if result.exitCode != 0 {
            if result.stderr.contains("-1743") || result.stderr.contains("not allowed") {
                throw AppleScriptError.automationPermissionDenied
            }
            throw AppleScriptError.scriptFailed(
                "permission-check",
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    public func exportAsset(
        identifier: String,
        to directory: URL,
        timeout: TimeInterval = defaultTimeout
    ) async throws -> URL {
        let bareUUID = stripLocalIdSuffix(identifier)

        guard isValidBareUUID(bareUUID) else {
            throw AppleScriptError.scriptFailed(bareUUID, "Invalid UUID format")
        }

        // Create per-asset subdirectory to isolate the exported filename
        let subdir = directory.appendingPathComponent("as_\(PathSafety.sanitizeFilename(bareUUID))")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        let script = buildExportScript(uuid: bareUUID, destination: subdir.path)
        let result = try await runOsascript(script: script, timeout: timeout)

        if result.exitCode != 0 {
            try? FileManager.default.removeItem(at: subdir)

            if result.stderr.contains("-1743") || result.stderr.contains("not allowed") {
                throw AppleScriptError.automationPermissionDenied
            }
            if result.timedOut {
                throw AppleScriptError.timeout(bareUUID, timeout)
            }
            throw AppleScriptError.scriptFailed(
                bareUUID,
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        // Discover the exported file(s)
        let contents = try FileManager.default.contentsOfDirectory(
            at: subdir,
            includingPropertiesForKeys: nil
        )
        let mediaFiles = contents.filter { isMediaFile($0) }

        guard !mediaFiles.isEmpty else {
            try? FileManager.default.removeItem(at: subdir)
            throw AppleScriptError.noFileProduced(bareUUID)
        }

        // For Live Photos (HEIC + MOV), prefer the image component
        if mediaFiles.count > 1,
           let imageFile = mediaFiles.first(where: { isImageFile($0) }) {
            for file in mediaFiles where file != imageFile {
                try? FileManager.default.removeItem(at: file)
            }
            return imageFile
        }

        return mediaFiles[0]
    }
}

// MARK: - Script execution

/// Wrapper around `Process` and `Pipe` for safe cross-isolation use.
///
/// ## Safety (`@unchecked Sendable`)
/// The wrapped Foundation types are set up before the process runs and read
/// only after it exits (via `terminationHandler`). No concurrent mutation occurs.
private final class ProcessHandle: @unchecked Sendable {
    let process = Process()
    let stderrPipe = Pipe()
    var timeoutWork: DispatchWorkItem?

    func configure(script: String) {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice
    }

    func readStderr() -> String {
        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct OsascriptResult: Sendable {
    let exitCode: Int32
    let stderr: String
    let timedOut: Bool
}

private func runOsascript(script: String, timeout: TimeInterval) async throws -> OsascriptResult {
    let handle = ProcessHandle()
    handle.configure(script: script)

    return try await withCheckedThrowingContinuation { continuation in
        // Timeout: terminate process after deadline (cancellable to allow clean exit).
        // Stored on handle (@unchecked Sendable) so it can be cancelled from
        // terminationHandler without capturing a non-Sendable local.
        handle.timeoutWork = DispatchWorkItem {
            if handle.process.isRunning {
                handle.process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: handle.timeoutWork!)

        handle.process.terminationHandler = { proc in
            handle.timeoutWork?.cancel()
            handle.timeoutWork = nil
            let stderr = handle.readStderr()
            // Detect our timeout by checking for uncaught signal (SIGTERM = 15)
            let timedOut = proc.terminationReason == .uncaughtSignal
            continuation.resume(returning: OsascriptResult(
                exitCode: proc.terminationStatus,
                stderr: stderr,
                timedOut: timedOut
            ))
        }

        do {
            try handle.process.run()
        } catch {
            handle.timeoutWork?.cancel()
            handle.timeoutWork = nil
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - Helpers

private func buildExportScript(uuid: String, destination: String) -> String {
    let safeUUID = escapeForAppleScript(uuid)
    let safeDest = escapeForAppleScript(destination)
    // AppleScript export command — Photos.app handles iCloud download transparently
    return """
    tell application "Photos"
        set thePic to media item id "\(safeUUID)"
        export {thePic} to POSIX file "\(safeDest)" with using originals
    end tell
    """
}

/// Escape a string for safe interpolation into AppleScript string literals.
/// Prevents injection by neutralizing `\` and `"` characters.
func escapeForAppleScript(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

/// Validate that a string is a standard UUID (8-4-4-4-12 hex digits).
func isValidBareUUID(_ string: String) -> Bool {
    let pattern = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/
    return string.wholeMatch(of: pattern) != nil
}

/// Strip "/L0/001" suffix from PhotoKit local identifier to get bare UUID.
public func stripLocalIdSuffix(_ identifier: String) -> String {
    if let slashIndex = identifier.firstIndex(of: "/") {
        return String(identifier[identifier.startIndex..<slashIndex])
    }
    return identifier
}

/// Check available disk space at a given path.
public func availableDiskSpace(at path: URL) -> UInt64 {
    let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path.path)
    return (attrs?[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
}

private let imageExtensions: Set<String> = [
    "heic", "jpg", "jpeg", "png", "tiff", "tif", "gif",
    "dng", "cr2", "nef", "orf", "arw", "raw",
]
private let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi"]

private func isMediaFile(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return imageExtensions.contains(ext) || videoExtensions.contains(ext)
}

private func isImageFile(_ url: URL) -> Bool {
    imageExtensions.contains(url.pathExtension.lowercased())
}

// MARK: - Errors

public enum AppleScriptError: LocalizedError, Sendable {
    case automationPermissionDenied
    case timeout(String, TimeInterval)
    case scriptFailed(String, String)
    case noFileProduced(String)

    public var errorDescription: String? {
        switch self {
        case .automationPermissionDenied:
            return "Automation permission required: grant ladder access to Photos "
                + "in System Settings > Privacy & Security > Automation"
        case .timeout(let uuid, let seconds):
            return "AppleScript export timed out after \(Int(seconds))s for asset \(uuid)"
        case .scriptFailed(let uuid, let message):
            return "AppleScript export failed for asset \(uuid): \(message)"
        case .noFileProduced(let uuid):
            return "AppleScript export produced no file for asset \(uuid)"
        }
    }
}
