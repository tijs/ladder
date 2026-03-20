import Foundation

/// Lightweight metadata about a photo or video asset.
///
/// Core fields (identifier, dates, dimensions, location, etc.) are populated
/// from PhotoKit. Enrichment fields (keywords, people, description, editor)
/// come from Photos.sqlite via ``PhotosDatabase`` since PhotoKit doesn't
/// expose them.
public struct AssetInfo: Sendable {
    // MARK: - PhotoKit fields

    public let identifier: String
    public let creationDate: Date?
    public let kind: AssetKind
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let latitude: Double?
    public let longitude: Double?
    public let isFavorite: Bool
    public let originalFilename: String?
    public let uniformTypeIdentifier: String?
    public let hasEdit: Bool
    public let albums: [AlbumInfo]

    // MARK: - Enrichment fields (from Photos.sqlite)

    public var keywords: [String]
    public var people: [PersonInfo]
    public var assetDescription: String?
    public var editedAt: Date?
    public var editor: String?

    /// The UUID portion of the PhotoKit local identifier.
    ///
    /// PhotoKit `localIdentifier` is formatted as `UUID/L0/001`.
    /// Photos.sqlite `ZUUID` is just the UUID. This property extracts
    /// the UUID prefix for joining between the two systems.
    public var uuid: String {
        if let slashIndex = identifier.firstIndex(of: "/") {
            return String(identifier[identifier.startIndex..<slashIndex])
        }
        return identifier
    }

    public init(
        identifier: String,
        creationDate: Date?,
        kind: AssetKind,
        pixelWidth: Int,
        pixelHeight: Int,
        latitude: Double?,
        longitude: Double?,
        isFavorite: Bool,
        originalFilename: String?,
        uniformTypeIdentifier: String?,
        hasEdit: Bool,
        albums: [AlbumInfo],
        keywords: [String] = [],
        people: [PersonInfo] = [],
        assetDescription: String? = nil,
        editedAt: Date? = nil,
        editor: String? = nil
    ) {
        self.identifier = identifier
        self.creationDate = creationDate
        self.kind = kind
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.latitude = latitude
        self.longitude = longitude
        self.isFavorite = isFavorite
        self.originalFilename = originalFilename
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.hasEdit = hasEdit
        self.albums = albums
        self.keywords = keywords
        self.people = people
        self.assetDescription = assetDescription
        self.editedAt = editedAt
        self.editor = editor
    }
}

/// The type of media asset.
public enum AssetKind: Int, Sendable, Codable {
    case photo = 0
    case video = 1
}

/// Reference to an album containing the asset.
public struct AlbumInfo: Sendable, Codable, Equatable {
    public let identifier: String
    public let title: String

    public init(identifier: String, title: String) {
        self.identifier = identifier
        self.title = title
    }
}

/// Reference to a recognized person in the asset.
public struct PersonInfo: Sendable, Codable, Equatable {
    public let uuid: String
    public let displayName: String

    public init(uuid: String, displayName: String) {
        self.uuid = uuid
        self.displayName = displayName
    }
}
