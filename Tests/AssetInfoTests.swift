import Foundation
import Testing

@testable import LadderKit

@Suite("AssetInfo")
struct AssetInfoTests {
    @Test("creates photo asset with all fields")
    func createPhotoAsset() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let album = AlbumInfo(identifier: "album-1", title: "Vacation")
        let info = AssetInfo(
            identifier: "ABC-123",
            creationDate: date,
            kind: .photo,
            pixelWidth: 4032,
            pixelHeight: 3024,
            latitude: 52.3676,
            longitude: 4.9041,
            isFavorite: true,
            originalFilename: "IMG_0001.HEIC",
            uniformTypeIdentifier: "public.heic",
            hasEdit: false,
            albums: [album]
        )

        #expect(info.identifier == "ABC-123")
        #expect(info.creationDate == date)
        #expect(info.kind == .photo)
        #expect(info.pixelWidth == 4032)
        #expect(info.pixelHeight == 3024)
        #expect(info.latitude == 52.3676)
        #expect(info.longitude == 4.9041)
        #expect(info.isFavorite == true)
        #expect(info.originalFilename == "IMG_0001.HEIC")
        #expect(info.uniformTypeIdentifier == "public.heic")
        #expect(info.hasEdit == false)
        #expect(info.albums.count == 1)
        #expect(info.albums[0].title == "Vacation")
    }

    @Test("creates video asset with nil optional fields")
    func createVideoAssetMinimal() {
        let info = AssetInfo(
            identifier: "VID-456",
            creationDate: nil,
            kind: .video,
            pixelWidth: 1920,
            pixelHeight: 1080,
            latitude: nil,
            longitude: nil,
            isFavorite: false,
            originalFilename: nil,
            uniformTypeIdentifier: nil,
            hasEdit: false,
            albums: []
        )

        #expect(info.identifier == "VID-456")
        #expect(info.creationDate == nil)
        #expect(info.kind == .video)
        #expect(info.latitude == nil)
        #expect(info.originalFilename == nil)
        #expect(info.albums.isEmpty)
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
}

@Suite("MockPhotoLibrary Discovery")
struct MockPhotoLibraryDiscoveryTests {
    @Test("enumerateAssets returns configured assets")
    func enumerateAssets() {
        let infos = [
            AssetInfo(
                identifier: "asset-1",
                creationDate: Date(),
                kind: .photo,
                pixelWidth: 100,
                pixelHeight: 100,
                latitude: nil,
                longitude: nil,
                isFavorite: false,
                originalFilename: "photo.jpg",
                uniformTypeIdentifier: "public.jpeg",
                hasEdit: false,
                albums: []
            ),
            AssetInfo(
                identifier: "asset-2",
                creationDate: nil,
                kind: .video,
                pixelWidth: 1920,
                pixelHeight: 1080,
                latitude: nil,
                longitude: nil,
                isFavorite: true,
                originalFilename: "video.mov",
                uniformTypeIdentifier: "com.apple.quicktime-movie",
                hasEdit: true,
                albums: [AlbumInfo(identifier: "a1", title: "Favorites")]
            ),
        ]

        let library = MockPhotoLibrary(assets: [:], assetInfos: infos)

        #expect(library.totalAssetCount() == 2)

        let enumerated = library.enumerateAssets()
        #expect(enumerated.count == 2)
        #expect(enumerated[0].identifier == "asset-1")
        #expect(enumerated[1].identifier == "asset-2")
        #expect(enumerated[1].isFavorite == true)
        #expect(enumerated[1].hasEdit == true)
        #expect(enumerated[1].albums.count == 1)
    }

    @Test("totalAssetCount returns zero for empty library")
    func emptyLibrary() {
        let library = MockPhotoLibrary(assets: [:])
        #expect(library.totalAssetCount() == 0)
        #expect(library.enumerateAssets().isEmpty)
    }
}
