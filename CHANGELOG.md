# Changelog

## 0.6.1

Additive convenience for callers that re-key export results. `attic` (the
primary consumer) needs to translate exporter outputs from PhotoKit local
UUIDs to `PHCloudIdentifier`s post-migration. Previously every translation
site rebuilt the struct field-by-field, which silently drops new fields if
the type ever grows.

- `ExportResult.withUUID(_:)` — returns a copy with a different `uuid`,
  preserving `path`, `size`, `sha256` (and any future fields).
- `ExportError.withUUID(_:)` — returns a copy preserving `message` and
  `classification` (and the derived `unavailable` legacy flag).

No API removals. Existing struct initializers and field access patterns
keep working unchanged.

## 0.6.0

Cross-device asset identity. Adds an optional cloud-stable identifier so
callers can correlate the same iCloud Photos asset across multiple Macs
signed into the same library.

- `AssetInfo.cloudIdentifier: String?` — new optional field. When set,
  `AssetInfo.uuid` resolves to the cloud identifier; otherwise it falls back
  to the device-local UUID prefix of `identifier` (existing behavior).
  `AssetInfo.legacyLocalIdentifier` is exposed as a computed property so
  callers can persist the legacy id alongside the canonical uuid.
- `AssetInfo.withResolvedCloudIdentity(_:)` — non-mutating helper that
  applies a `CloudMappingResult` to a copy of the asset.
- `CloudMappingResult` (enum) — stable surface for per-asset resolver
  outcomes: `.cloud(String)`, `.notFound`, `.multipleFound`, `.error(String)`.
  Maps `PHPhotosError.identifierNotFound` and `.multipleIdentifiersFound`
  onto distinct cases so callers don't conflate genuinely-local assets with
  shared/merged-library collisions.
- `CloudIdentityResolving` (protocol) + `PhotoKitCloudIdentityResolver` —
  wraps `PHPhotoLibrary.cloudIdentifierMappings(forLocalIdentifiers:)`.
  Chunks input at 1000 ids per call (defensive — Apple does not document a
  cap but warns the API is "expensive"). Retries `.error` results once with
  a 500ms delay before treating them as terminal, absorbing the iOS
  18.1.1 / Sequoia 15.x async-quirk where the first call returns spurious
  errors.
- `AssetInfo.uuid` is now a computed property derived from
  `cloudIdentifier ?? legacyLocalIdentifier`. The JSON wire format no longer
  includes a redundant `uuid` field; existing v0.5.x consumers that
  decoded `uuid` directly should switch to `identifier` (full localId) or
  read `uuid` from the new computed accessor after decoding. v1 JSON without
  `cloudIdentifier` still decodes correctly.

## 0.5.1

Review-driven fixes on top of 0.5.0. No API removals; additive only.

- `AppleScriptError.assetUnavailable(uuid, message)` — new case raised when
  Photos.app reports `-1728 "Can't get media item"`. Retrying is pointless for
  these (typically shared-album assets whose derivative is gone server-side).
  `PhotoExporter` maps this to `ExportClassification.permanentlyUnavailable`
  and reports `.permanentFailure` to the adaptive controller, so the iCloud
  lane doesn't throttle down on genuinely-dead assets.
- `ScriptFailure` now carries a `classification`, so per-asset classification
  flows through the AppleScript fallback path instead of being flattened to
  `.transientCloud`.
- `PhotoKitLibrary.fetchAssets(identifiers:)` now keys the returned dict by
  whatever the caller passed in (bare UUID or full `"UUID/L0/001"` local
  identifier). Previously it always returned PhotoKit's full identifier, and
  callers had to split the string. Makes the UUID contract explicit at the
  library boundary.
- `PhotoKitLibrary.loadEnrichedAssets(libraryURL:)` — static convenience that
  enumerates assets and applies Photos.sqlite enrichment in one call.
- `PhotosDatabaseLocalAvailability.fromLibrary(at:)` — static convenience that
  locates the library's `Photos.sqlite` and loads the locally-available UUID
  set in one call.

## 0.5.0

Adaptive export: partition a batch into local vs. iCloud work, and let the
caller throttle the iCloud lane when Photos/iCloud pushes back. LadderKit
supplies the mechanism (partitioning, protocol, outcome reporting); the
caller owns the policy (the actual controller implementation).

- `PhotosDatabase.localAvailableUUIDs(dbPath:)` — returns the set of asset
  UUIDs whose original resource is cached locally (via
  `ZINTERNALRESOURCE.ZLOCALAVAILABILITY = 1`).
- `LocalAvailabilityProviding` protocol + `PhotosDatabaseLocalAvailability`
  implementation backed by that query.
- `AdaptiveConcurrencyControlling` protocol and `ExportOutcome` enum. The
  protocol is observation-only: `currentLimit()` and `record(_:)`. The
  exporter polls the limit between dispatches — no shared permit bookkeeping.
  LadderKit ships no concrete controller; plug in your own policy.
- `ExportError.classification: ExportClassification` — `other`,
  `transientCloud`, or `permanentlyUnavailable`. Backward-compatible: legacy
  payloads without the field decode as `other`, or `permanentlyUnavailable`
  when the legacy `unavailable == true` flag is set.
- `PhotoExporter.export(uuids:localAvailability:adaptiveController:)` — new
  optional parameters. When provided, the exporter runs two lanes in
  parallel: the local lane at `maxConcurrency`, the iCloud lane gated by the
  controller's current limit. The AppleScript fallback is now also parallel
  and gated by the same controller. Proper cancellation: the group is
  cancelled when `Task.isCancelled` trips.

Fully backward compatible with 0.4.x — existing call sites keep working.

## 0.4.0

- `AssetHandle` exposes `isShared: Bool` (from `PHAsset.sourceType == .typeCloudShared`)
- `ExportError` gains an `unavailable: Bool` flag for failures that should
  not be retried (e.g. shared-album assets whose iCloud derivative has failed
  server-side). Backward-compatible default `false`; decoder tolerates
  payloads without the field.
- `PhotoExporter.export` short-circuits shared-album assets that fail
  PhotoKit: the AppleScript fallback goes through the same shared-stream
  pipeline and also fails (after a 5-minute server-side timeout), so we
  mark these as `unavailable` immediately instead of retrying.

## 0.3.4

- Include iCloud Shared Photo Library assets in `enumerateAssets()` and
  `totalAssetCount()` by adding `.typeCloudShared` to PhotoKit fetch options

## 0.3.3

- Harden AppleScript export: make `buildExportScript` private, detect
  permission errors via exit code 77

## 0.3.2

- Fix process hang: cancel timeout timer when osascript exits normally

## 0.3.1

- Retry PhotoKit export failures via AppleScript fallback within the same
  batch instead of only using AppleScript for initially-missing assets

## 0.3.0

- AppleScript fallback for iCloud-only assets that PhotoKit cannot export
  directly (Optimize Storage enabled, asset not downloaded)
- Photos.app handles the iCloud download transparently via `export` command
- Configurable timeout per asset (default 600s)

## 0.2.0

LadderKit is now a library product that can be consumed by other Swift packages.

- Expose LadderKit as a `.library` product in Package.swift
- Add asset discovery API: `enumerateAssets()` and `totalAssetCount()` on `PhotoLibrary` protocol
- Add `AssetInfo`, `AssetKind`, `AlbumInfo`, and `PersonInfo` model types
- Add `PhotosDatabase` for reading enrichment metadata from Photos.sqlite (keywords, people, descriptions, albums, filenames, edit details)
- Add `PhotosLibraryPath` for validating `.photoslibrary` bundles and deriving database paths
- All enrichment uses Photos.sqlite (single-pass, no per-asset PhotoKit XPC calls)
- `AssetInfo` conforms to `Codable` with JSON key mapping (`description` for `assetDescription`)
- Use throwing `FileHandle.write(contentsOf:)` for disk-full safety during export
- Fully backwards compatible: existing CLI JSON protocol is unchanged

## 0.1.0

Initial release.

- Export original photo/video files from the iCloud Photos library via PhotoKit
- Batch processing: accepts multiple UUIDs per invocation
- JSON protocol over stdin/stdout for integration with attic
- SHA-256 checksums computed during export
- Staging directory for exported files with configurable path
- Makefile with install/uninstall targets
