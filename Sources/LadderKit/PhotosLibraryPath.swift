import Foundation

/// Utilities for working with Photos library bundle paths.
///
/// A Photos library is a bundle (directory) at a user-chosen location,
/// typically `~/Pictures/Photos Library.photoslibrary`. The internal
/// database lives at `database/Photos.sqlite` within the bundle.
public enum PhotosLibraryPath {
    /// The path suffix from the library bundle root to Photos.sqlite.
    static let databaseRelativePath = "database/Photos.sqlite"

    /// Derive the Photos.sqlite path from a library bundle URL.
    ///
    /// - Parameter libraryURL: URL to the `.photoslibrary` bundle
    ///   (e.g., from NSOpenPanel or a saved bookmark).
    /// - Returns: The full path to Photos.sqlite, or `nil` if the
    ///   library doesn't contain the expected database file.
    public static func databasePath(for libraryURL: URL) -> String? {
        let dbURL = libraryURL
            .appendingPathComponent("database")
            .appendingPathComponent("Photos.sqlite")
        let path = dbURL.path

        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    /// Validate that a URL points to a Photos library bundle.
    ///
    /// Checks that:
    /// - The URL has a `.photoslibrary` extension
    /// - The directory exists
    /// - It contains `database/Photos.sqlite`
    public static func validate(_ url: URL) -> ValidationResult {
        guard url.pathExtension == "photoslibrary" else {
            return .invalid("Not a Photos library (expected .photoslibrary extension)")
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            return .invalid("Photos library not found at \(url.path)")
        }

        guard databasePath(for: url) != nil else {
            return .invalid("Photos library does not contain a database")
        }

        return .valid
    }

    public enum ValidationResult: Equatable {
        case valid
        case invalid(String)

        public var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
    }
}
