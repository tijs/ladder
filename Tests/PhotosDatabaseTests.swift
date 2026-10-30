import Foundation
import SQLite3
import Testing

@testable import LadderKit

@Suite("PhotosDatabase")
struct PhotosDatabaseTests {
    @Test("readEnrichment reads old and macOS 27 album relationships", arguments: [33, 34])
    func readAlbumRelationships(number: Int) throws {
        try withPhotosDatabase(sql: photosAlbumFixtureSQL + photosAlbumJoinSQL(number: number)) { path in
            let data = PhotosDatabase.readEnrichment(dbPath: path)
            #expect(data.albums == [
                "asset-1": [
                    AlbumInfo(identifier: "album-1", title: "Vacation"),
                    AlbumInfo(identifier: "album-2", title: "Family")
                ],
                "asset-2": [AlbumInfo(identifier: "album-2", title: "Family")]
            ])
        }
    }

    @Test("album discovery supports future table and asset column numbering")
    func readFutureAlbumRelationships() throws {
        try withPhotosDatabase(sql: photosAlbumFixtureSQL + photosAlbumJoinSQL(number: 99, assetNumber: 42)) { path in
            let albums = PhotosDatabase.readEnrichment(dbPath: path).albums
            #expect(albums["asset-1"] == [
                AlbumInfo(identifier: "album-1", title: "Vacation"),
                AlbumInfo(identifier: "album-2", title: "Family")
            ])
            #expect(albums["asset-2"] == [AlbumInfo(identifier: "album-2", title: "Family")])
        }
    }

    @Test("album memberships are unique, ordered and limited to valid non-trashed records")
    func readAlbumMembershipFiltering() throws {
        let sql = photosAlbumFixtureSQL + photosAlbumJoinSQL(number: 34) + """
            ALTER TABLE ZGENERICALBUM ADD COLUMN ZTRASHEDSTATE INTEGER DEFAULT 0;
            INSERT INTO ZGENERICALBUM VALUES
                (30, 'null-title', NULL, 0), (40, NULL, 'No UUID', 0), (50, 'deleted-album', 'Deleted', 1);
            INSERT INTO ZASSET VALUES (0, 'asset-zero', 0), (4, NULL, 0);
            DELETE FROM Z_34ASSETS;
            INSERT INTO Z_34ASSETS VALUES
                (1, 20), (1, 10), (1, 20), (2, 20), (3, 10), (999, 10), (4, 10),
                (NULL, 10), ('invalid', 10), (1.5, 10), (1, NULL), (1, 999), (1, 30), (1, 40), (1, 50);
            """
        try withPhotosDatabase(sql: sql) { path in
            #expect(PhotosDatabase.readEnrichment(dbPath: path).albums == [
                "asset-1": [
                    AlbumInfo(identifier: "album-1", title: "Vacation"),
                    AlbumInfo(identifier: "album-2", title: "Family")
                ],
                "asset-2": [AlbumInfo(identifier: "album-2", title: "Family")]
            ])
        }
    }

    @Test("discovery ignores unrelated tables, views and unsafe lookalike identifiers")
    func readAlbumIgnoresUnrelatedSchema() throws {
        let sql = photosAlbumFixtureSQL + photosAlbumJoinSQL(number: 34) + """
            CREATE TABLE Z_1ASSETS (Z_3ASSETS INTEGER, ZOWNER INTEGER);
            CREATE TABLE Z_32ASSETS (Z_3ASSETS INTEGER, Z_99ALBUMS INTEGER);
            CREATE TABLE Z_35ASSETS (Z_35ALBUMS INTEGER);
            CREATE TABLE Z_36ASSETS (Z_3ASSETS INTEGER);
            CREATE TABLE Z_37ASSETS (Z_3ASSETS INTEGER, Z_4ASSETS INTEGER, Z_37ALBUMS INTEGER);
            CREATE TABLE Z_40ASSETS (Z_3ASSETS INTEGER, Z_40ALBUMS INTEGER, Z_41ALBUMS INTEGER);
            CREATE TABLE OTHER (Z_3ASSETS INTEGER, Z_33ALBUMS INTEGER);
            CREATE VIEW Z_38ASSETS AS SELECT Z_3ASSETS, Z_34ALBUMS AS Z_38ALBUMS FROM Z_34ASSETS;
            CREATE TABLE "Z_39ASSETS""; DROP TABLE ZASSET; --" (Z_3ASSETS INTEGER, Z_39ALBUMS INTEGER);
            """
        try withPhotosDatabase(sql: sql) { path in
            let data = PhotosDatabase.readEnrichment(dbPath: path)
            #expect(data.albums["asset-2"] == [AlbumInfo(identifier: "album-2", title: "Family")])
            #expect(data.albums.count == 2)
        }
    }

    @Test("ambiguous join tables skip albums regardless of creation order", arguments: [false, true])
    func readAmbiguousAlbumSchema(reversed: Bool) throws {
        let joins = reversed
            ? photosAlbumJoinSQL(number: 34) + photosAlbumJoinSQL(number: 33)
            : photosAlbumJoinSQL(number: 33) + photosAlbumJoinSQL(number: 34)
        try withPhotosDatabase(sql: photosAlbumFixtureSQL + photosOtherEnrichmentFixtureSQL + joins) { path in
            let data = PhotosDatabase.readEnrichment(dbPath: path)
            #expect(data.albums.isEmpty)
            expectOtherEnrichment(data)
        }
    }

    @Test("unsupported joins preserve other enrichment", arguments: [
        "",
        "CREATE TABLE Z_34ASSETS (Z_3ASSETS INTEGER);",
        "CREATE TABLE Z_34ASSETS (Z_34ALBUMS INTEGER);",
        "CREATE TABLE Z_34ASSETS (Z_3ASSETS INTEGER, Z_33ALBUMS INTEGER);",
        "CREATE TABLE Z_34ASSETS (Z_3ASSETS INTEGER, Z_4ASSETS INTEGER, Z_34ALBUMS INTEGER);",
        "CREATE TABLE Z_34ASSETS (Z_3ASSETS INTEGER, Z_34ALBUMS INTEGER, Z_35ALBUMS INTEGER);",
        "CREATE TABLE Z_34ASSETS (Z_3ASSETS INTEGER, Z_34ALBUMS INTEGER);"
    ])
    func readUnsupportedAlbumSchema(joinSQL: String) throws {
        try withPhotosDatabase(sql: photosAlbumFixtureSQL + photosOtherEnrichmentFixtureSQL + joinSQL) { path in
            let data = PhotosDatabase.readEnrichment(dbPath: path)
            #expect(data.albums.isEmpty)
            expectOtherEnrichment(data)
        }
    }

    @Test("missing album table or columns preserve other enrichment", arguments: ["table", "Z_PK", "ZUUID", "ZTITLE"])
    func readIncompleteAlbumTable(missing: String) throws {
        let columns = ["Z_PK INTEGER", "ZUUID TEXT", "ZTITLE TEXT"]
            .filter { !$0.hasPrefix(missing + " ") }.joined(separator: ", ")
        let albumSQL = missing == "table" ? "" : "CREATE TABLE ZGENERICALBUM (\(columns));"
        let sql = photosAlbumFixtureSQL + photosOtherEnrichmentFixtureSQL + photosAlbumJoinSQL(number: 34) + """
            DROP TABLE ZGENERICALBUM;
            \(albumSQL)
            """
        try withPhotosDatabase(sql: sql) { path in
            let data = PhotosDatabase.readEnrichment(dbPath: path)
            #expect(data.albums.isEmpty)
            expectOtherEnrichment(data)
        }
    }

    @Test("readEnrichment leaves a read-only database and its directory unchanged")
    func readEnrichmentIsReadOnly() throws {
        try withPhotosDatabase(sql: photosAlbumFixtureSQL + photosAlbumJoinSQL(number: 34)) { path in
            let url = URL(fileURLWithPath: path)
            let directory = url.deletingLastPathComponent()
            try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: path)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
            let before = try Data(contentsOf: url)
            let filesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            let data = PhotosDatabase.readEnrichment(dbPath: path)
            #expect(data.albums.count == 2)
            #expect(try Data(contentsOf: url) == before)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == filesBefore)
        }
    }

    @Test("missing, inaccessible and malformed paths return empty data without creating a database")
    func readEnrichmentInvalidDatabases() throws {
        try withPhotosDatabase(sql: "") { path in
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
            let missing = directory.appendingPathComponent("missing.sqlite").path
            expectEmptyEnrichment(PhotosDatabase.readEnrichment(dbPath: missing))
            #expect(!FileManager.default.fileExists(atPath: missing))
            // A directory cannot be opened as a database, even under a privileged test runner.
            expectEmptyEnrichment(PhotosDatabase.readEnrichment(dbPath: directory.path))
            try Data("This is not a SQLite database".utf8).write(to: URL(fileURLWithPath: path))
            expectEmptyEnrichment(PhotosDatabase.readEnrichment(dbPath: path))
        }
    }

    private func expectOtherEnrichment(_ data: PhotosDatabase.EnrichmentData) {
        #expect(data.filenames["asset-1"]?.originalFilename == "IMG_0001.HEIC")
        #expect(data.filenames["asset-1"]?.uniformTypeIdentifier == "public.heic")
        #expect(data.keywords["asset-1"] == ["sunset"])
        #expect(data.people["asset-1"] == [PersonInfo(uuid: "person-1", displayName: "Alice")])
        #expect(data.descriptions["asset-1"] == "A sunset")
        #expect(data.edits["asset-1"]?.editor == "com.apple.photos")
        #expect(data.edits["asset-1"]?.editedAt == Date(timeIntervalSince1970: 978_308_200))
    }

    private func expectEmptyEnrichment(_ data: PhotosDatabase.EnrichmentData) {
        #expect(data.filenames.isEmpty)
        #expect(data.albums.isEmpty)
        #expect(data.keywords.isEmpty)
        #expect(data.people.isEmpty)
        #expect(data.descriptions.isEmpty)
        #expect(data.edits.isEmpty)
    }
}

extension PhotosDatabaseTests {
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
