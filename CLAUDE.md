# Ladder

Swift library and CLI for accessing the macOS Photos library. Part of the photo-cloud system (companion: [attic](https://github.com/tijs/attic)).

## Commands

```bash
swift build -c release | xcsift    # Build release binary
swift test | xcsift                 # Run tests (63 tests)
swiftlint --fix                    # Auto-fix lint issues
```

## Architecture

- **LadderKit** (library product): consumed by other Swift packages via SPM
  - `PhotoLibrary` protocol + `PhotoKitLibrary` — asset discovery and export via PhotoKit. `fetchAssets` preserves caller-provided identifier keys (bare UUID or full `"UUID/L0/001"`). `loadEnrichedAssets(libraryURL:)` is a one-call convenience that enumerates + enriches.
  - `PhotosDatabase` — reads Photos.sqlite for metadata enrichment (keywords, people, descriptions, albums, filenames, edits) and local-availability flags.
  - `PhotosLibraryPath` — validates `.photoslibrary` bundles, derives database paths
  - `PhotoExporter` — concurrent file export with inline SHA-256 hashing. Partitions a batch into local vs. iCloud lanes; the iCloud lane can be throttled by an `AdaptiveConcurrencyControlling` controller.
  - `LocalAvailabilityProviding` + `PhotosDatabaseLocalAvailability` — tells the exporter which assets are cached locally (`ZLOCALAVAILABILITY = 1`) so iCloud-only work can be isolated. Use `.fromLibrary(at:)` for one-call setup.
  - `AdaptiveConcurrencyControlling` + `ExportOutcome` — observation-only protocol for tuning the iCloud lane. LadderKit ships no concrete controller; callers own the policy. Outcomes are `.success`, `.transientFailure`, `.permanentFailure`.
  - `AppleScriptRunner` / `ScriptExporter` — iCloud-only fallback via Photos.app. Detects `-1728 "Can't get media item"` and raises `AppleScriptError.assetUnavailable`, which the exporter maps to `ExportClassification.permanentlyUnavailable`.
  - `ExportError.classification` — `.other`, `.transientCloud`, or `.permanentlyUnavailable`. Flows end-to-end so callers can route retry/skip decisions without string-matching.
  - `StreamingHasher` / `FileHasher` — incremental and one-shot SHA-256
  - `PathSafety` — filename sanitization and path traversal prevention
  - `AssetInfo`, `AlbumInfo`, `PersonInfo`, `AssetKind` — data models (all `Codable` + `Sendable`)
- **CLI** (executable): thin JSON-in/JSON-out wrapper around `PhotoExporter`. Kept for ad-hoc use; the Swift `attic` CLI consumes LadderKit directly as a library.

## Key Design Decisions

- **PhotoKit for discovery/export, Photos.sqlite for enrichment**: PhotoKit provides core asset enumeration and file export (including transparent iCloud downloads). Photos.sqlite provides metadata PhotoKit doesn't expose (keywords, people, descriptions, albums, filenames, edit details). This hybrid approach gives complete metadata.
- **No per-asset XPC during enumeration**: `enumerateAssets()` only uses PHAsset properties. Expensive `PHAssetResource` calls are deferred to export time. Album membership comes from sqlite.
- **User selects library path**: No default Photos.sqlite path assumed. The consumer provides the `.photoslibrary` URL (e.g., from NSOpenPanel with a security-scoped bookmark). This avoids Full Disk Access and supports multiple/moved libraries.
- **`safeQuery` resilience**: Photos.sqlite schema varies across macOS versions. Enrichment queries silently return empty results if tables don't exist.

## Conventions

- Use `debugPrint()` instead of `print()` (stripped by compiler in release)
- Dependencies are injected for testability — no real PhotoKit calls in tests
- `StreamingHasher` uses `@unchecked Sendable` with `NSLock` — documented safety invariant in `Hasher.swift`. TODO: migrate to `Mutex<CC_SHA256_CTX>` when targeting macOS 15+
- Pipe all xcodebuild/swift commands through `xcsift` for clean output
- Files should stay under 500 lines
- Caseless namespace types use `enum` (e.g., `PhotosDatabase`, `PhotosLibraryPath`)

## Testing

All tests use mock implementations (`MockPhotoLibrary`, `MockAssetHandle`). No Photos library access, credentials, or network required. Tests verify:

- Export with inline hashing
- Path traversal prevention
- Photos.sqlite enrichment and in-place application
- Library path validation
- AssetInfo Codable round-trip (including `description` key mapping)
- UUID extraction from PhotoKit localIdentifier format
