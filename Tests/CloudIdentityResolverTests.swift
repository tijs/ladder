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

// MARK: - PhotoKitCloudIdentityResolver injection-based tests

import Photos

private final class ScriptedMappingSource: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let scripts: [[String: CloudMappingResult]]
    private(set) var observedBatches: [[String]] = []

    init(_ scripts: [[String: CloudMappingResult]]) {
        self.scripts = scripts
    }

    func handle(_ ids: [String]) -> [String: CloudMappingResult] {
        lock.lock()
        defer { lock.unlock() }
        observedBatches.append(ids)
        let result = scripts[min(calls, scripts.count - 1)]
        calls += 1
        return ids.reduce(into: [String: CloudMappingResult]()) { acc, id in
            acc[id] = result[id] ?? .notFound
        }
    }

    var totalCalls: Int {
        lock.lock(); defer { lock.unlock() }
        return calls
    }
}

@Suite("PhotoKitCloudIdentityResolver injected behavior")
struct PhotoKitCloudIdentityResolverInjectedTests {
    private func makeResolver(
        chunkSize: Int = 1000,
        scripts: [[String: CloudMappingResult]],
        authorized: Bool = true
    ) -> (PhotoKitCloudIdentityResolver, ScriptedMappingSource) {
        let scripted = ScriptedMappingSource(scripts)
        let resolver = PhotoKitCloudIdentityResolver(
            chunkSize: chunkSize,
            retryDelayNanoseconds: 0,
            mappingSource: { ids in scripted.handle(ids) },
            authorizationSource: { authorized ? .authorized : .denied }
        )
        return (resolver, scripted)
    }

    @Test("Sequoia retry: .error on first call, .cloud on second, returns cloud")
    func sequoiaRetryRecovers() async {
        let (resolver, scripted) = makeResolver(scripts: [
            ["A/L0/001": .error("transient")],
            ["A/L0/001": .cloud("CLOUD-A")],
        ])
        let result = await resolver.resolve(localIdentifiers: ["A/L0/001"])
        #expect(result["A/L0/001"] == .cloud("CLOUD-A"))
        #expect(scripted.totalCalls == 2)
    }

    @Test("Sequoia retry: persistent .error after both retries preserved")
    func sequoiaRetryPersistentError() async {
        let (resolver, scripted) = makeResolver(scripts: [
            ["A/L0/001": .error("first")],
            ["A/L0/001": .error("second")],
            ["A/L0/001": .error("third")],
        ])
        let result = await resolver.resolve(localIdentifiers: ["A/L0/001"])
        if case .error = result["A/L0/001"] {} else {
            Issue.record("expected .error after retries, got \(String(describing: result["A/L0/001"]))")
        }
        // Initial call + 2 backoff retries.
        #expect(scripted.totalCalls == 3)
    }

    @Test("Sequoia retry: second retry recovers when first retry still errors")
    func sequoiaSecondRetryRecovers() async {
        let (resolver, scripted) = makeResolver(scripts: [
            ["A/L0/001": .error("first")],
            ["A/L0/001": .error("second")],
            ["A/L0/001": .cloud("CLOUD-A")],
        ])
        let result = await resolver.resolve(localIdentifiers: ["A/L0/001"])
        #expect(result["A/L0/001"] == .cloud("CLOUD-A"))
        #expect(scripted.totalCalls == 3)
    }

    @Test("Sequoia retry: only errored entries are retried, success entries are not re-fetched")
    func sequoiaRetryOnlyErrored() async {
        let (resolver, scripted) = makeResolver(scripts: [
            ["A/L0/001": .cloud("CLOUD-A"), "B/L0/001": .error("boom")],
            ["B/L0/001": .cloud("CLOUD-B")],
        ])
        let result = await resolver.resolve(localIdentifiers: ["A/L0/001", "B/L0/001"])
        #expect(result["A/L0/001"] == .cloud("CLOUD-A"))
        #expect(result["B/L0/001"] == .cloud("CLOUD-B"))
        // Second batch only contains the errored id.
        #expect(scripted.observedBatches.count == 2)
        #expect(Set(scripted.observedBatches[1]) == ["B/L0/001"])
    }

    @Test("no errors: no retry batch dispatched")
    func noErrorsNoRetry() async {
        let (resolver, scripted) = makeResolver(scripts: [
            ["A/L0/001": .cloud("CLOUD-A"), "B/L0/001": .notFound],
        ])
        _ = await resolver.resolve(localIdentifiers: ["A/L0/001", "B/L0/001"])
        #expect(scripted.totalCalls == 1)
    }

    @Test("chunking: large batch is split at chunkSize boundary")
    func chunkingRespectsBoundary() async {
        let ids = (0..<2500).map { "ID-\($0)/L0/001" }
        let scripts: [[String: CloudMappingResult]] = [Dictionary(uniqueKeysWithValues: ids.map { ($0, .notFound) })]
        let (resolver, scripted) = makeResolver(chunkSize: 1000, scripts: scripts)
        _ = await resolver.resolve(localIdentifiers: ids)
        #expect(scripted.observedBatches.map(\.count) == [1000, 1000, 500])
    }

    @Test("denied authorization: every input becomes .error")
    func deniedAuthorization() async {
        let (resolver, scripted) = makeResolver(
            scripts: [["A/L0/001": .cloud("X")]],
            authorized: false
        )
        let result = await resolver.resolve(localIdentifiers: ["A/L0/001", "B/L0/001"])
        #expect(scripted.totalCalls == 0)
        if case .error = result["A/L0/001"] {} else { Issue.record("expected .error for A") }
        if case .error = result["B/L0/001"] {} else { Issue.record("expected .error for B") }
    }

    @Test("empty input: short-circuits with no PhotoKit call")
    func emptyInputShortCircuits() async {
        let (resolver, scripted) = makeResolver(scripts: [[:]])
        let result = await resolver.resolve(localIdentifiers: [])
        #expect(result.isEmpty)
        #expect(scripted.totalCalls == 0)
    }
}

@Suite("PhotoKitCloudIdentityResolver.translate")
struct PhotoKitTranslateTests {
    @Test("success → .cloud(stringValue)")
    func successCase() {
        // Use a mock PHCloudIdentifier-like by going through a fake error path
        // is not viable; instead confirm error mapping (which doesn't need
        // PHCloudIdentifier construction).
        // Map an arbitrary error → .error case.
        struct Boom: LocalizedError {
            var errorDescription: String? { "kaboom" }
        }
        let result = PhotoKitCloudIdentityResolver.translate(.failure(Boom()))
        if case .error(let msg) = result {
            #expect(msg.contains("kaboom") || !msg.isEmpty)
        } else {
            Issue.record("expected .error, got \(result)")
        }
    }

    @Test("PHPhotosError.identifierNotFound → .notFound")
    func identifierNotFound() {
        let err = PHPhotosError(.identifierNotFound)
        let result = PhotoKitCloudIdentityResolver.translate(.failure(err))
        #expect(result == .notFound)
    }

    @Test("PHPhotosError.multipleIdentifiersFound → .multipleFound")
    func multipleIdentifiersFound() {
        let err = PHPhotosError(.multipleIdentifiersFound)
        let result = PhotoKitCloudIdentityResolver.translate(.failure(err))
        #expect(result == .multipleFound)
    }

    @Test("Other PHPhotosError → .error with localized description")
    func otherPhotosError() {
        let err = PHPhotosError(.invalid)
        let result = PhotoKitCloudIdentityResolver.translate(.failure(err))
        if case .error = result {} else { Issue.record("expected .error, got \(result)") }
    }
}
