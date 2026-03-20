import Foundation

/// Lightweight metadata about a photo or video asset, populated from PhotoKit.
///
/// This struct is used for asset discovery and filtering — it carries enough
/// information to decide whether an asset needs backup and to build the
/// metadata JSON, without loading the asset's pixel data.
public struct AssetInfo: Sendable {
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
        albums: [AlbumInfo]
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
