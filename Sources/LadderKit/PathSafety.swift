import Foundation

public enum PathSafety {
    /// Sanitize a string for safe use as a filename component.
    /// Replaces path separators and other unsafe characters with underscores.
    public static func sanitizeFilename(_ name: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.unicodeScalars
            .map { unsafe.contains($0) ? "_" : String($0) }
            .joined()
    }

    /// Build a destination URL within stagingDir, validating the result stays inside it.
    public static func safeDestination(
        stagingDir: URL,
        uuid: String,
        originalFilename: String
    ) throws -> URL {
        let safeName = sanitizeFilename(uuid) + "_" + sanitizeFilename(originalFilename)
        let destURL = stagingDir.appendingPathComponent(safeName)

        let resolvedDest = destURL.standardizedFileURL.path
        let resolvedStaging = stagingDir.standardizedFileURL.path

        guard resolvedDest.hasPrefix(resolvedStaging) else {
            throw ExportFailure.unsafePath(uuid)
        }

        return destURL
    }

    /// Validate that a staging directory path is safe to use.
    public static func validateStagingDir(_ path: String) throws -> URL {
        guard !path.isEmpty else {
            throw ExportFailure.invalidStagingDir("Staging directory path is empty")
        }

        guard path.hasPrefix("/") else {
            throw ExportFailure.invalidStagingDir("Staging directory must be an absolute path: \(path)")
        }

        let forbidden = ["/System", "/Library", "/usr", "/bin", "/sbin", "/var", "/private/var"]
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        for prefix in forbidden where normalized == prefix || normalized.hasPrefix(prefix + "/") {
            throw ExportFailure.invalidStagingDir("Staging directory must not be inside \(prefix)")
        }

        return URL(fileURLWithPath: path)
    }
}
