import Foundation

/// Lightweight metadata about a photo or video asset.
///
/// Core fields (identifier, dates, dimensions, location) are populated
/// from PhotoKit during enumeration. All other fields (filename, albums,
/// keywords, people, description, edits) come from Photos.sqlite via
/// ``PhotosDatabase`` enrichment. The optional ``cloudIdentifier`` is
/// populated separately via ``CloudIdentityResolving``.
public struct AssetInfo: Sendable, Codable {
    // MARK: - PhotoKit fields (set during enumeration)

    public let identifier: String
    public let cloudIdentifier: String?
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

    /// Canonical asset uuid. Prefers ``cloudIdentifier`` when available
    /// (stable across all devices in the same iCloud Photos library); falls
    /// back to the device-local UUID prefix of ``identifier``.
    public var uuid: String {
        cloudIdentifier ?? Self.extractUUIDPrefix(from: identifier)
    }

    /// The device-local UUID prefix of ``identifier``. Stable for as long as
    /// the asset exists on this device, but differs across devices for the
    /// same iCloud asset.
    public var legacyLocalIdentifier: String {
        Self.extractUUIDPrefix(from: identifier)
    }

    enum CodingKeys: String, CodingKey {
        case identifier, cloudIdentifier, creationDate, kind
        case pixelWidth, pixelHeight, latitude, longitude, isFavorite
        case originalFilename, uniformTypeIdentifier, hasEdit
        case albums, keywords, people
        case assetDescription = "description"
        case editedAt, editor
    }

    public init(
        identifier: String,
        cloudIdentifier: String? = nil,
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
        self.cloudIdentifier = cloudIdentifier
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

    /// Returns a copy with cloud identity applied from a resolver result.
    /// `.notFound`, `.multipleFound`, and `.error` keep ``cloudIdentifier``
    /// nil so ``uuid`` falls back to the local UUID prefix.
    public func withResolvedCloudIdentity(_ result: CloudMappingResult) -> AssetInfo {
        guard case .cloud(let cloudId) = result else { return self }
        return AssetInfo(
            identifier: identifier,
            cloudIdentifier: cloudId,
            creationDate: creationDate,
            kind: kind,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            latitude: latitude,
            longitude: longitude,
            isFavorite: isFavorite,
            originalFilename: originalFilename,
            uniformTypeIdentifier: uniformTypeIdentifier,
            hasEdit: hasEdit,
            albums: albums,
            keywords: keywords,
            people: people,
            assetDescription: assetDescription,
            editedAt: editedAt,
            editor: editor
        )
    }

    private static func extractUUIDPrefix(from identifier: String) -> String {
        if let slashIndex = identifier.firstIndex(of: "/") {
            return String(identifier[identifier.startIndex..<slashIndex])
        }
        return identifier
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
