import Foundation
import SQLite3
import Testing

@testable import LadderKit

@Suite("PhotosDatabase")
struct PhotosDatabaseTests {
    @Test("enrich applies filenames to matching assets")
    func enrichFilenames() {
        var assets = [makeAsset(identifier: "ABC-123/L0/001")]
        let data = PhotosDatabase.EnrichmentData(
            filenames: ["ABC-123": .init(
                originalFilename: "IMG_0001.HEIC",
                uniformTypeIdentifier: "public.heic"
            )],
            albums: [:],
            keywords: [:],
            people: [:],
            descriptions: [:],
            edits: [:]
        )

        PhotosDatabase.enrich(&assets, with: data)

        #expect(assets[0].originalFilename == "IMG_0001.HEIC")
        #expect(assets[0].uniformTypeIdentifier == "public.heic")
    }

    @Test("enrich applies albums to matching assets")
    func enrichAlbums() {
        var assets = [makeAsset(identifier: "ABC-123/L0/001")]
        let data = PhotosDatabase.EnrichmentData(
            filenames: [:],
            albums: ["ABC-123": [AlbumInfo(identifier: "a1", title: "Vacation")]],
            keywords: [:],
            people: [:],
            descriptions: [:],
            edits: [:]
        )

        PhotosDatabase.enrich(&assets, with: data)

        #expect(assets[0].albums.count == 1)
        #expect(assets[0].albums[0].title == "Vacation")
    }

    @Test("enrich applies keywords to matching assets")
    func enrichKeywords() {
        var assets = [makeAsset(identifier: "ABC-123/L0/001")]
        let data = PhotosDatabase.EnrichmentData(
            filenames: [:],
            albums: [:],
            keywords: ["ABC-123": ["sunset", "beach"]],
            people: [:],
            descriptions: [:],
            edits: [:]
        )

        PhotosDatabase.enrich(&assets, with: data)

        #expect(assets[0].keywords == ["sunset", "beach"])
    }

    @Test("enrich applies people to matching assets")
    func enrichPeople() {
        var assets = [makeAsset(identifier: "DEF-456/L0/001")]
        let person = PersonInfo(uuid: "person-1", displayName: "Alice")
        let data = PhotosDatabase.EnrichmentData(
            filenames: [:],
            albums: [:],
            keywords: [:],
            people: ["DEF-456": [person]],
            descriptions: [:],
            edits: [:]
        )

        PhotosDatabase.enrich(&assets, with: data)

        #expect(assets[0].people.count == 1)
        #expect(assets[0].people[0].displayName == "Alice")
    }

    @Test("enrich applies descriptions to matching assets")
    func enrichDescriptions() {
        var assets = [makeAsset(identifier: "GHI-789/L0/001")]
        let data = PhotosDatabase.EnrichmentData(
            filenames: [:],
            albums: [:],
            keywords: [:],
            people: [:],
            descriptions: ["GHI-789": "A beautiful sunset"],
            edits: [:]
        )

        PhotosDatabase.enrich(&assets, with: data)

        #expect(assets[0].assetDescription == "A beautiful sunset")
    }

    @Test("enrich applies edit info and sets hasEdit flag")
    func enrichEdits() {
        var assets = [makeAsset(identifier: "JKL-012/L0/001")]
        #expect(assets[0].hasEdit == false)

        let editDate = Date(timeIntervalSince1970: 1_700_000_000)
        let data = PhotosDatabase.EnrichmentData(
            filenames: [:],
            albums: [:],
            keywords: [:],
            people: [:],
            descriptions: [:],
            edits: ["JKL-012": .init(editedAt: editDate, editor: "com.apple.photos")]
        )

        PhotosDatabase.enrich(&assets, with: data)

        #expect(assets[0].hasEdit == true)
        #expect(assets[0].editedAt == editDate)
        #expect(assets[0].editor == "com.apple.photos")
    }

    @Test("enrich leaves unmatched assets unchanged")
    func enrichNoMatch() {
        var assets = [makeAsset(identifier: "NOMATCH/L0/001")]
        let data = PhotosDatabase.EnrichmentData(
            filenames: [:],
            albums: [:],
            keywords: ["OTHER": ["tag"]],
            people: [:],
            descriptions: [:],
            edits: [:]
        )

        PhotosDatabase.enrich(&assets, with: data)

        #expect(assets[0].keywords.isEmpty)
        #expect(assets[0].people.isEmpty)
        #expect(assets[0].assetDescription == nil)
        #expect(assets[0].editor == nil)
        #expect(assets[0].originalFilename == nil)
        #expect(assets[0].albums.isEmpty)
    }

    @Test("enrich handles multiple assets")
    func enrichMultiple() {
        var assets = [
            makeAsset(identifier: "A/L0/001"),
            makeAsset(identifier: "B/L0/001"),
            makeAsset(identifier: "C/L0/001"),
        ]
        let data = PhotosDatabase.EnrichmentData(
            filenames: [:],
            albums: [:],
            keywords: ["A": ["nature"], "C": ["urban"]],
            people: [:],
            descriptions: ["B": "Photo B"],
            edits: [:]
        )

        PhotosDatabase.enrich(&assets, with: data)

        #expect(assets[0].keywords == ["nature"])
        #expect(assets[1].assetDescription == "Photo B")
        #expect(assets[2].keywords == ["urban"])
    }

    @Test("readEnrichment returns empty for nonexistent database")
    func readEnrichmentMissingDb() {
        let data = PhotosDatabase.readEnrichment(dbPath: "/nonexistent/path.sqlite")
        #expect(data.keywords.isEmpty)
        #expect(data.people.isEmpty)
        #expect(data.descriptions.isEmpty)
        #expect(data.edits.isEmpty)
        #expect(data.filenames.isEmpty)
        #expect(data.albums.isEmpty)
    }

    @Test("readEnrichment handles empty database")
    func readEnrichmentEmptyDb() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ladder-db-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("Photos.sqlite").path

        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        sqlite3_close(db)

        let data = PhotosDatabase.readEnrichment(dbPath: dbPath)
        #expect(data.keywords.isEmpty)
        #expect(data.people.isEmpty)
        #expect(data.filenames.isEmpty)
        #expect(data.albums.isEmpty)
    }
}
