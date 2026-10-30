import Foundation
import SQLite3
import Testing

/// A disposable database containing only synthetic metadata; never opens Photos.
func withPhotosDatabase(
    sql: String,
    test: (String) throws -> Void
) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ladder-db-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("Photos.sqlite").path

    do {
        var connection: OpaquePointer?
        let result = sqlite3_open(path, &connection)
        defer { if let connection { sqlite3_close(connection) } }
        try #require(result == SQLITE_OK)
        let database = try #require(connection)
        let executed = sqlite3_exec(database, sql, nil, nil, nil)
        #expect(executed == SQLITE_OK, "Fixture SQL: \(String(cString: sqlite3_errmsg(database)))")
        try #require(executed == SQLITE_OK)
    }
    try test(path)
}

let photosAlbumFixtureSQL = """
    CREATE TABLE ZASSET (Z_PK INTEGER PRIMARY KEY, ZUUID TEXT, ZTRASHEDSTATE INTEGER);
    INSERT INTO ZASSET VALUES (1, 'asset-1', 0), (2, 'asset-2', 0), (3, 'trashed', 1);
    CREATE TABLE ZGENERICALBUM (Z_PK INTEGER PRIMARY KEY, ZUUID TEXT, ZTITLE TEXT);
    INSERT INTO ZGENERICALBUM VALUES
        (10, 'album-1', 'Vacation'), (20, 'album-2', 'Family');
    """

func photosAlbumJoinSQL(number: Int, assetNumber: Int = 3) -> String {
    """
    CREATE TABLE Z_\(number)ASSETS (Z_\(assetNumber)ASSETS INTEGER, Z_\(number)ALBUMS INTEGER);
    INSERT INTO Z_\(number)ASSETS VALUES (1, 10), (1, 20), (2, 20);
    """
}

let photosOtherEnrichmentFixtureSQL = """
    ALTER TABLE ZASSET ADD COLUMN ZUNIFORMTYPEIDENTIFIER TEXT;
    UPDATE ZASSET SET ZUNIFORMTYPEIDENTIFIER = 'public.heic' WHERE Z_PK = 1;
    CREATE TABLE ZADDITIONALASSETATTRIBUTES (
        Z_PK INTEGER PRIMARY KEY, ZASSET INTEGER, ZORIGINALFILENAME TEXT, ZUNMANAGEDADJUSTMENT INTEGER
    );
    INSERT INTO ZADDITIONALASSETATTRIBUTES VALUES (100, 1, 'IMG_0001.HEIC', 200);
    CREATE TABLE ZKEYWORD (Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT);
    INSERT INTO ZKEYWORD VALUES (1, 'sunset');
    CREATE TABLE Z_1KEYWORDS (Z_52KEYWORDS INTEGER, Z_1ASSETATTRIBUTES INTEGER);
    INSERT INTO Z_1KEYWORDS VALUES (1, 100);
    CREATE TABLE ZASSETDESCRIPTION (ZASSETATTRIBUTES INTEGER, ZLONGDESCRIPTION TEXT);
    INSERT INTO ZASSETDESCRIPTION VALUES (100, 'A sunset');
    CREATE TABLE ZPERSON (Z_PK INTEGER PRIMARY KEY, ZPERSONUUID TEXT, ZDISPLAYNAME TEXT);
    INSERT INTO ZPERSON VALUES (1, 'person-1', 'Alice');
    CREATE TABLE ZDETECTEDFACE (ZASSETFORFACE INTEGER, ZPERSONFORFACE INTEGER, ZHIDDEN INTEGER, ZASSETVISIBLE INTEGER);
    INSERT INTO ZDETECTEDFACE VALUES (1, 1, 0, 1);
    CREATE TABLE ZINTERNALRESOURCE (ZASSET INTEGER, ZRESOURCETYPE INTEGER, ZTRASHEDSTATE INTEGER, ZVERSION INTEGER);
    INSERT INTO ZINTERNALRESOURCE VALUES (1, 1, 0, 1);
    CREATE TABLE ZUNMANAGEDADJUSTMENT (
        Z_PK INTEGER PRIMARY KEY, ZADJUSTMENTTIMESTAMP REAL, ZADJUSTMENTFORMATIDENTIFIER TEXT
    );
    INSERT INTO ZUNMANAGEDADJUSTMENT VALUES (200, 1000, 'com.apple.photos');
    """
