import Foundation

/// Lightweight metadata about a photo or video asset.
///
/// Core fields (identifier, dates, dimensions, location) are populated
/// from PhotoKit during enumeration. All other fields (filename, albums,
/// keywords, people, description, edits) come from Photos.sqlite via
/// ``PhotosDatabase`` enrichment.
public struct AssetInfo: Sendable, Codable {
    // MARK: - PhotoKit fields (set during enumeration)

    public let identifier: String
    public let uuid: String
    public let creationDate: Date?
    public let kind: AssetKind
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let latitude: Double?
    public let longitude: Double?
    public let isFavorite: Bool

    // MARK: - Enrichment fields (from Photos.sqlite)

    public var originalFilename: String?
    public var uniformTypeIdentifier: String?
    public var hasEdit: Bool
    public var albums: [AlbumInfo]
    public var keywords: [String]
    public var people: [PersonInfo]
    public var assetDescription: String?
    public var editedAt: Date?
    public var editor: String?

    enum CodingKeys: String, CodingKey {
        case identifier, uuid, creationDate, kind
        case pixelWidth, pixelHeight, latitude, longitude, isFavorite
        case originalFilename, uniformTypeIdentifier, hasEdit
        case albums, keywords, people
        case assetDescription = "description"
        case editedAt, editor
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
        originalFilename: String? = nil,
        uniformTypeIdentifier: String? = nil,
        hasEdit: Bool = false,
        albums: [AlbumInfo] = [],
        keywords: [String] = [],
        people: [PersonInfo] = [],
        assetDescription: String? = nil,
        editedAt: Date? = nil,
        editor: String? = nil
    ) {
        self.identifier = identifier
        // Extract UUID from PhotoKit localIdentifier format "UUID/L0/001"
        if let slashIndex = identifier.firstIndex(of: "/") {
            self.uuid = String(identifier[identifier.startIndex..<slashIndex])
        } else {
            self.uuid = identifier
        }
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
