import Foundation
import Testing

@testable import LadderKit

@Suite("CloudMappingResult")
struct CloudMappingResultTests {
    @Test("equatable distinguishes all cases")
    func equatable() {
        #expect(CloudMappingResult.cloud("a") == CloudMappingResult.cloud("a"))
        #expect(CloudMappingResult.cloud("a") != CloudMappingResult.cloud("b"))
        #expect(CloudMappingResult.notFound == CloudMappingResult.notFound)
        #expect(CloudMappingResult.multipleFound == CloudMappingResult.multipleFound)
        #expect(CloudMappingResult.error("x") == CloudMappingResult.error("x"))
        #expect(CloudMappingResult.error("x") != CloudMappingResult.error("y"))
        #expect(CloudMappingResult.notFound != CloudMappingResult.multipleFound)
    }
}

@Suite("AssetInfo cloud identity")
struct AssetInfoCloudIdentityTests {
    @Test("uuid prefers cloud identifier when set")
    func uuidPrefersCloud() {
        let info = AssetInfo(
            identifier: "ABC-123/L0/001",
            cloudIdentifier: "CLOUD-XYZ-999",
            creationDate: nil,
            kind: .photo,
            pixelWidth: 1, pixelHeight: 1,
            latitude: nil, longitude: nil,
            isFavorite: false
        )
        #expect(info.uuid == "CLOUD-XYZ-999")
        #expect(info.legacyLocalIdentifier == "ABC-123")
    }

    @Test("uuid falls back to local prefix when cloud nil")
    func uuidFallsBackToLocal() {
        let info = AssetInfo(
            identifier: "ABC-123/L0/001",
            cloudIdentifier: nil,
            creationDate: nil,
            kind: .photo,
            pixelWidth: 1, pixelHeight: 1,
            latitude: nil, longitude: nil,
            isFavorite: false
        )
        #expect(info.uuid == "ABC-123")
        #expect(info.legacyLocalIdentifier == "ABC-123")
    }

    @Test("withResolvedCloudIdentity .cloud sets cloudIdentifier")
    func withResolvedCloud() {
        let info = AssetInfo(
            identifier: "ABC-123/L0/001",
            creationDate: nil,
            kind: .photo,
            pixelWidth: 1, pixelHeight: 1,
            latitude: nil, longitude: nil,
            isFavorite: false
        )
        let resolved = info.withResolvedCloudIdentity(.cloud("CLOUD-ID"))
        #expect(resolved.cloudIdentifier == "CLOUD-ID")
        #expect(resolved.uuid == "CLOUD-ID")
        #expect(resolved.legacyLocalIdentifier == "ABC-123")
        // identifier preserved
        #expect(resolved.identifier == "ABC-123/L0/001")
    }

    @Test("withResolvedCloudIdentity .notFound preserves no-cloud state")
    func withResolvedNotFound() {
        let info = AssetInfo(
            identifier: "ABC-123/L0/001",
            creationDate: nil,
            kind: .photo,
            pixelWidth: 1, pixelHeight: 1,
            latitude: nil, longitude: nil,
            isFavorite: false
        )
        let resolved = info.withResolvedCloudIdentity(.notFound)
        #expect(resolved.cloudIdentifier == nil)
        #expect(resolved.uuid == "ABC-123")
    }

    @Test("withResolvedCloudIdentity .multipleFound preserves no-cloud state")
    func withResolvedMultiple() {
        let info = AssetInfo(
            identifier: "ABC-123/L0/001",
            creationDate: nil,
            kind: .photo,
            pixelWidth: 1, pixelHeight: 1,
            latitude: nil, longitude: nil,
            isFavorite: false
        )
        let resolved = info.withResolvedCloudIdentity(.multipleFound)
        #expect(resolved.cloudIdentifier == nil)
        #expect(resolved.uuid == "ABC-123")
    }

    @Test("withResolvedCloudIdentity .error preserves no-cloud state")
    func withResolvedError() {
        let info = AssetInfo(
            identifier: "ABC-123/L0/001",
            creationDate: nil,
            kind: .photo,
            pixelWidth: 1, pixelHeight: 1,
            latitude: nil, longitude: nil,
            isFavorite: false
        )
        let resolved = info.withResolvedCloudIdentity(.error("boom"))
        #expect(resolved.cloudIdentifier == nil)
        #expect(resolved.uuid == "ABC-123")
    }

    @Test("withResolvedCloudIdentity preserves enrichment fields")
    func withResolvedPreservesEnrichment() {
        let info = AssetInfo(
            identifier: "ABC-123/L0/001",
            creationDate: Date(timeIntervalSince1970: 1),
            kind: .video,
            pixelWidth: 100, pixelHeight: 200,
            latitude: 1.0, longitude: 2.0,
            isFavorite: true,
            originalFilename: "test.mov",
            uniformTypeIdentifier: "public.mpeg-4",
            hasEdit: true,
            albums: [AlbumInfo(identifier: "a1", title: "Album")],
            keywords: ["tag"],
            people: [PersonInfo(uuid: "p1", displayName: "Name")],
            assetDescription: "desc",
            editedAt: Date(timeIntervalSince1970: 2),
            editor: "com.test"
        )
        let resolved = info.withResolvedCloudIdentity(.cloud("CID"))
        #expect(resolved.cloudIdentifier == "CID")
        #expect(resolved.kind == .video)
        #expect(resolved.originalFilename == "test.mov")
        #expect(resolved.albums.count == 1)
        #expect(resolved.keywords == ["tag"])
        #expect(resolved.people[0].uuid == "p1")
        #expect(resolved.assetDescription == "desc")
        #expect(resolved.isFavorite == true)
        #expect(resolved.hasEdit == true)
    }

    @Test("Codable round-trip preserves cloudIdentifier")
    func codableRoundTripWithCloud() throws {
        let original = AssetInfo(
            identifier: "ABC/L0/001",
            cloudIdentifier: "CLOUD-1",
            creationDate: nil,
            kind: .photo,
            pixelWidth: 1, pixelHeight: 1,
            latitude: nil, longitude: nil,
            isFavorite: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AssetInfo.self, from: data)
        #expect(decoded.cloudIdentifier == "CLOUD-1")
        #expect(decoded.uuid == "CLOUD-1")
    }

    @Test("Codable decodes legacy JSON without cloudIdentifier")
    func codableDecodesLegacyJSON() throws {
        let legacyJSON = """
        {
            "identifier": "ABC/L0/001",
            "kind": 0,
            "pixelWidth": 1,
            "pixelHeight": 1,
            "isFavorite": false,
            "hasEdit": false,
            "albums": [],
            "keywords": [],
            "people": []
        }
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(AssetInfo.self, from: data)
        #expect(decoded.cloudIdentifier == nil)
        #expect(decoded.uuid == "ABC")
        #expect(decoded.legacyLocalIdentifier == "ABC")
    }
}

// MARK: - Mock resolver for downstream tests

/// In-memory `CloudIdentityResolving` for tests. Records every call.
public actor MockCloudIdentityResolver: CloudIdentityResolving {
    public var mappings: [String: CloudMappingResult]
    public private(set) var callCount: Int = 0
    public private(set) var observedBatches: [[String]] = []

    public init(mappings: [String: CloudMappingResult] = [:]) {
        self.mappings = mappings
    }

    public func setMappings(_ new: [String: CloudMappingResult]) {
        self.mappings = new
    }

    nonisolated public func resolve(localIdentifiers: [String]) async -> [String: CloudMappingResult] {
        await record(localIdentifiers)
        return await read(localIdentifiers)
    }

    private func record(_ ids: [String]) {
        callCount += 1
        observedBatches.append(ids)
    }

    private func read(_ ids: [String]) -> [String: CloudMappingResult] {
        var result: [String: CloudMappingResult] = [:]
        for id in ids {
            result[id] = mappings[id] ?? .notFound
        }
        return result
    }
}

@Suite("MockCloudIdentityResolver")
struct MockCloudIdentityResolverTests {
    @Test("returns configured mappings for known ids")
    func returnsConfiguredMappings() async {
        let resolver = MockCloudIdentityResolver(mappings: [
            "A/L0/001": .cloud("CLOUD-A"),
            "B/L0/001": .notFound,
            "C/L0/001": .multipleFound,
            "D/L0/001": .error("boom"),
        ])
        let result = await resolver.resolve(localIdentifiers: [
            "A/L0/001", "B/L0/001", "C/L0/001", "D/L0/001",
        ])
        #expect(result["A/L0/001"] == .cloud("CLOUD-A"))
        #expect(result["B/L0/001"] == .notFound)
        #expect(result["C/L0/001"] == .multipleFound)
        #expect(result["D/L0/001"] == .error("boom"))
    }

    @Test("unknown ids default to .notFound")
    func unknownIdsNotFound() async {
        let resolver = MockCloudIdentityResolver()
        let result = await resolver.resolve(localIdentifiers: ["UNKNOWN/L0/001"])
        #expect(result["UNKNOWN/L0/001"] == .notFound)
    }

    @Test("empty input returns empty result")
    func emptyInput() async {
        let resolver = MockCloudIdentityResolver()
        let result = await resolver.resolve(localIdentifiers: [])
        #expect(result.isEmpty)
        let count = await resolver.callCount
        #expect(count == 1)
    }

    @Test("records per-batch invocations")
    func recordsBatches() async {
        let resolver = MockCloudIdentityResolver(mappings: ["X/L0/001": .cloud("X-CID")])
        _ = await resolver.resolve(localIdentifiers: ["X/L0/001"])
        _ = await resolver.resolve(localIdentifiers: ["Y/L0/001", "Z/L0/001"])
        let batches = await resolver.observedBatches
        #expect(batches.count == 2)
        #expect(batches[0] == ["X/L0/001"])
        #expect(batches[1] == ["Y/L0/001", "Z/L0/001"])
    }
}
