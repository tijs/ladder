import Foundation
import SQLite3

/// Reads enrichment metadata from Photos.sqlite that PhotoKit doesn't expose:
/// keywords, people/faces, descriptions, and edit details.
///
/// Opens the database read-only and closes it after building the enrichment maps.
/// Uses `safeQuery` for resilience across macOS versions where table schemas differ.
public struct PhotosDatabase: Sendable {
    /// Default path to the Photos library database.
    public static let defaultPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Pictures/Photos Library.photoslibrary/database/Photos.sqlite"
    }()

    /// CoreData epoch (2001-01-01) offset from Unix epoch in seconds.
    static let coreDataEpochOffset: TimeInterval = 978_307_200

    /// All enrichment data, keyed by Photos.sqlite ZUUID.
    public struct EnrichmentData: Sendable {
        public let keywords: [String: [String]]
        public let people: [String: [PersonInfo]]
        public let descriptions: [String: String]
        public let edits: [String: EditInfo]

        public static let empty = EnrichmentData(
            keywords: [:], people: [:], descriptions: [:], edits: [:]
        )
    }

    /// Edit information from Photos.sqlite.
    public struct EditInfo: Sendable {
        public let editedAt: Date?
        public let editor: String
    }

    private init() {}

    /// Read all enrichment data from Photos.sqlite.
    ///
    /// Opens the database read-only, runs enrichment queries, and closes it.
    /// Returns `.empty` if the database cannot be opened.
    public static func readEnrichment(
        dbPath: String = defaultPath
    ) -> EnrichmentData {
        guard let db = openDatabase(path: dbPath) else {
            return .empty
        }
        defer { sqlite3_close(db) }

        let uuidMap = buildUUIDMap(db: db)

        return EnrichmentData(
            keywords: buildKeywordMap(db: db, uuidMap: uuidMap),
            people: buildPeopleMap(db: db, uuidMap: uuidMap),
            descriptions: buildDescriptionMap(db: db, uuidMap: uuidMap),
            edits: buildEditMap(db: db, uuidMap: uuidMap)
        )
    }

    /// Apply enrichment data to an array of assets in-place.
    ///
    /// Matches assets by their `uuid` property (extracted from PhotoKit's
    /// localIdentifier) against the enrichment maps keyed by Photos.sqlite ZUUID.
    public static func enrich(
        _ assets: inout [AssetInfo],
        with data: EnrichmentData
    ) {
        for i in assets.indices {
            let uuid = assets[i].uuid
            if let kw = data.keywords[uuid] {
                assets[i].keywords = kw
            }
            if let ppl = data.people[uuid] {
                assets[i].people = ppl
            }
            if let desc = data.descriptions[uuid] {
                assets[i].assetDescription = desc
            }
            if let edit = data.edits[uuid] {
                assets[i].editedAt = edit.editedAt
                assets[i].editor = edit.editor
            }
        }
    }
}

// MARK: - SQLite Helpers

extension PhotosDatabase {
    private static func openDatabase(path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return nil
        }
        return db
    }

    /// Execute a query with resilience — returns empty results if the table
    /// doesn't exist (schema varies across macOS versions).
    private static func safeQuery(
        db: OpaquePointer,
        sql: String,
        label: String,
        handler: (OpaquePointer) -> Void
    ) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            handler(stmt!)
        }
    }

    private static func stringColumn(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    private static func doubleColumn(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return sqlite3_column_double(stmt, index)
    }

    private static func intColumn(_ stmt: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, index))
    }
}

// MARK: - UUID Map (Z_PK → ZUUID)

extension PhotosDatabase {
    /// Build a map from Z_PK (integer primary key) to ZUUID (string).
    /// Enrichment queries return Z_PK references; we need ZUUID for matching
    /// against PhotoKit's localIdentifier.
    private static func buildUUIDMap(db: OpaquePointer) -> [Int: String] {
        var map: [Int: String] = [:]
        safeQuery(
            db: db,
            sql: "SELECT Z_PK, ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0",
            label: "uuid map"
        ) { stmt in
            let pk = intColumn(stmt, 0)
            if let uuid = stringColumn(stmt, 1) {
                map[pk] = uuid
            }
        }
        return map
    }
}

// MARK: - Enrichment Queries

extension PhotosDatabase {
    private static func buildDescriptionMap(
        db: OpaquePointer,
        uuidMap: [Int: String]
    ) -> [String: String] {
        var map: [String: String] = [:]
        safeQuery(
            db: db,
            sql: """
                SELECT aa.ZASSET, d.ZLONGDESCRIPTION
                FROM ZASSETDESCRIPTION d
                JOIN ZADDITIONALASSETATTRIBUTES aa ON d.ZASSETATTRIBUTES = aa.Z_PK
                WHERE d.ZLONGDESCRIPTION IS NOT NULL AND d.ZLONGDESCRIPTION != ''
                """,
            label: "descriptions"
        ) { stmt in
            let pk = intColumn(stmt, 0)
            if let uuid = uuidMap[pk], let desc = stringColumn(stmt, 1) {
                map[uuid] = desc
            }
        }
        return map
    }

    private static func buildKeywordMap(
        db: OpaquePointer,
        uuidMap: [Int: String]
    ) -> [String: [String]] {
        var map: [String: [String]] = [:]
        safeQuery(
            db: db,
            sql: """
                SELECT aa.ZASSET, k.ZTITLE
                FROM Z_1KEYWORDS jk
                JOIN ZKEYWORD k ON jk.Z_52KEYWORDS = k.Z_PK
                JOIN ZADDITIONALASSETATTRIBUTES aa ON jk.Z_1ASSETATTRIBUTES = aa.Z_PK
                WHERE k.ZTITLE IS NOT NULL
                """,
            label: "keywords"
        ) { stmt in
            let pk = intColumn(stmt, 0)
            if let uuid = uuidMap[pk], let title = stringColumn(stmt, 1) {
                map[uuid, default: []].append(title)
            }
        }
        return map
    }

    private static func buildPeopleMap(
        db: OpaquePointer,
        uuidMap: [Int: String]
    ) -> [String: [PersonInfo]] {
        var map: [String: [PersonInfo]] = [:]
        var seen: [String: Set<String>] = [:]
        safeQuery(
            db: db,
            sql: """
                SELECT df.ZASSETFORFACE, p.ZPERSONUUID, p.ZDISPLAYNAME
                FROM ZDETECTEDFACE df
                JOIN ZPERSON p ON df.ZPERSONFORFACE = p.Z_PK
                WHERE p.ZDISPLAYNAME IS NOT NULL AND p.ZDISPLAYNAME != ''
                  AND df.ZHIDDEN = 0 AND df.ZASSETVISIBLE = 1
                """,
            label: "people"
        ) { stmt in
            let assetPK = intColumn(stmt, 0)
            guard let uuid = uuidMap[assetPK],
                  let personUUID = stringColumn(stmt, 1),
                  let displayName = stringColumn(stmt, 2)
            else { return }

            if seen[uuid, default: []].contains(personUUID) { return }
            seen[uuid, default: []].insert(personUUID)

            map[uuid, default: []].append(
                PersonInfo(uuid: personUUID, displayName: displayName)
            )
        }
        return map
    }

    private static func buildEditMap(
        db: OpaquePointer,
        uuidMap: [Int: String]
    ) -> [String: EditInfo] {
        // First, build the set of assets that have rendered resources
        var renderedAssets: Set<Int> = []
        safeQuery(
            db: db,
            sql: """
                SELECT DISTINCT ir.ZASSET
                FROM ZINTERNALRESOURCE ir
                WHERE ir.ZRESOURCETYPE = 1
                  AND ir.ZTRASHEDSTATE = 0
                  AND ir.ZVERSION != 0
                """,
            label: "rendered resources"
        ) { stmt in
            renderedAssets.insert(intColumn(stmt, 0))
        }

        // Then build edit map, requiring both adjustment AND rendered resource
        var map: [String: EditInfo] = [:]
        safeQuery(
            db: db,
            sql: """
                SELECT aa.ZASSET, ua.ZADJUSTMENTTIMESTAMP, ua.ZADJUSTMENTFORMATIDENTIFIER
                FROM ZADDITIONALASSETATTRIBUTES aa
                JOIN ZUNMANAGEDADJUSTMENT ua ON aa.ZUNMANAGEDADJUSTMENT = ua.Z_PK
                WHERE aa.ZUNMANAGEDADJUSTMENT IS NOT NULL
                  AND ua.ZADJUSTMENTFORMATIDENTIFIER IS NOT NULL
                """,
            label: "edits"
        ) { stmt in
            let pk = intColumn(stmt, 0)
            guard renderedAssets.contains(pk),
                  let uuid = uuidMap[pk],
                  let editor = stringColumn(stmt, 2)
            else { return }

            let editedAt: Date? = doubleColumn(stmt, 1).map { timestamp in
                Date(timeIntervalSince1970: timestamp + coreDataEpochOffset)
            }
            map[uuid] = EditInfo(editedAt: editedAt, editor: editor)
        }
        return map
    }
}
