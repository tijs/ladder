import Foundation
import Testing

@testable import LadderKit

@Suite("AssetInfo")
struct AssetInfoTests {
    @Test("creates photo asset with all fields")
    func createPhotoAsset() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let album = AlbumInfo(identifier: "album-1", title: "Vacation")
        let person = PersonInfo(uuid: "person-1", displayName: "Bob")
        let info = AssetInfo(
            identifier: "ABC-123/L0/001",
            creationDate: date,
            kind: .photo,
            pixelWidth: 4032,
            pixelHeight: 3024,
            latitude: 52.3676,
            longitude: 4.9041,
            isFavorite: true,
            originalFilename: "IMG_0001.HEIC",
            uniformTypeIdentifier: "public.heic",
            hasEdit: true,
            albums: [album],
            keywords: ["sunset", "beach"],
            people: [person],
            assetDescription: "A nice photo",
            editedAt: date,
            editor: "com.apple.photos"
        )

        #expect(info.identifier == "ABC-123/L0/001")
        #expect(info.uuid == "ABC-123")
        #expect(info.creationDate == date)
        #expect(info.kind == .photo)
        #expect(info.pixelWidth == 4032)
        #expect(info.pixelHeight == 3024)
        #expect(info.latitude == 52.3676)
        #expect(info.longitude == 4.9041)
        #expect(info.isFavorite == true)
        #expect(info.originalFilename == "IMG_0001.HEIC")
        #expect(info.uniformTypeIdentifier == "public.heic")
        #expect(info.hasEdit == true)
        #expect(info.albums.count == 1)
        #expect(info.albums[0].title == "Vacation")
        #expect(info.keywords == ["sunset", "beach"])
        #expect(info.people.count == 1)
        #expect(info.people[0].displayName == "Bob")
        #expect(info.assetDescription == "A nice photo")
        #expect(info.editedAt == date)
        #expect(info.editor == "com.apple.photos")
    }

    @Test("creates video asset with default enrichment fields")
    func createVideoAssetMinimal() {
        let info = makeAsset(identifier: "VID-456/L0/001", kind: .video)

        #expect(info.uuid == "VID-456")
        #expect(info.kind == .video)
        #expect(info.keywords.isEmpty)
        #expect(info.people.isEmpty)
        #expect(info.assetDescription == nil)
        #expect(info.editedAt == nil)
        #expect(info.editor == nil)
        #expect(info.originalFilename == nil)
        #expect(info.albums.isEmpty)
        #expect(info.hasEdit == false)
    }

    @Test("uuid extraction from localIdentifier")
    func uuidExtraction() {
        let withSuffix = makeAsset(identifier: "AAAA-BBBB-CCCC/L0/001")
        #expect(withSuffix.uuid == "AAAA-BBBB-CCCC")

        let withoutSuffix = makeAsset(identifier: "PLAIN-UUID")
        #expect(withoutSuffix.uuid == "PLAIN-UUID")
    }

    @Test("asset kind raw values match CLI constants")
    func assetKindRawValues() {
        #expect(AssetKind.photo.rawValue == 0)
        #expect(AssetKind.video.rawValue == 1)
    }

    @Test("album info equality")
    func albumInfoEquality() {
        let a = AlbumInfo(identifier: "id-1", title: "Photos")
        let b = AlbumInfo(identifier: "id-1", title: "Photos")
        let c = AlbumInfo(identifier: "id-2", title: "Videos")

        #expect(a == b)
        #expect(a != c)
    }

    @Test("person info equality")
    func personInfoEquality() {
        let a = PersonInfo(uuid: "p-1", displayName: "Alice")
        let b = PersonInfo(uuid: "p-1", displayName: "Alice")
        let c = PersonInfo(uuid: "p-2", displayName: "Bob")

        #expect(a == b)
        #expect(a != c)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = AssetInfo(
            identifier: "TEST/L0/001",
            creationDate: date,
            kind: .photo,
            pixelWidth: 100,
            pixelHeight: 200,
            latitude: 1.0,
            longitude: 2.0,
            isFavorite: true,
            originalFilename: "test.jpg",
            uniformTypeIdentifier: "public.jpeg",
            hasEdit: true,
            albums: [AlbumInfo(identifier: "a1", title: "Album")],
            keywords: ["tag"],
            people: [PersonInfo(uuid: "p1", displayName: "Name")],
            assetDescription: "A test",
            editedAt: date,
            editor: "com.test"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(AssetInfo.self, from: data)

        #expect(decoded.identifier == original.identifier)
        #expect(decoded.uuid == original.uuid)
        #expect(decoded.kind == original.kind)
        #expect(decoded.assetDescription == "A test")
        #expect(decoded.keywords == ["tag"])

        // Verify "description" is the JSON key, not "assetDescription"
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["description"] != nil)
        #expect(json["assetDescription"] == nil)
    }
}

@Suite("MockPhotoLibrary Discovery")
struct MockPhotoLibraryDiscoveryTests {
    @Test("enumerateAssets returns configured assets")
    func enumerateAssets() {
        let infos = [
            makeAsset(identifier: "asset-1/L0/001"),
            makeAsset(identifier: "asset-2/L0/001", kind: .video, isFavorite: true),
        ]

        let library = MockPhotoLibrary(assets: [:], assetInfos: infos)

        #expect(library.totalAssetCount() == 2)

        let enumerated = library.enumerateAssets()
        #expect(enumerated.count == 2)
        #expect(enumerated[0].uuid == "asset-1")
        #expect(enumerated[1].uuid == "asset-2")
        #expect(enumerated[1].isFavorite == true)
    }

    @Test("totalAssetCount returns zero for empty library")
    func emptyLibrary() {
        let library = MockPhotoLibrary(assets: [:])
        #expect(library.totalAssetCount() == 0)
        #expect(library.enumerateAssets().isEmpty)
    }
}

// MARK: - Test Helpers

func makeAsset(
    identifier: String,
    kind: AssetKind = .photo,
    isFavorite: Bool = false
) -> AssetInfo {
    AssetInfo(
        identifier: identifier,
        creationDate: nil,
        kind: kind,
        pixelWidth: 100,
        pixelHeight: 100,
        latitude: nil,
        longitude: nil,
        isFavorite: isFavorite
    )
}
