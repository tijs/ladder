<p align="center">
  <img src="ladder-logo.png" width="128" alt="ladder logo">
</p>

# ladder

A Swift library and CLI for accessing the macOS Photos library. LadderKit provides asset discovery, metadata enrichment, and file export via PhotoKit and Photos.sqlite.

## LadderKit Library

Add LadderKit as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tijs/ladder", from: "0.2.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [.product(name: "LadderKit", package: "ladder")]
    ),
]
```

Requires macOS 13+.

## API

### Asset Discovery

Enumerate all non-trashed assets in the Photos library via PhotoKit:

```swift
import LadderKit

let library = PhotoKitLibrary()
let count = library.totalAssetCount()
var assets = library.enumerateAssets()
// assets: [AssetInfo] sorted by creation date, newest first
```

Each `AssetInfo` contains core PhotoKit fields: identifier, creation date, media type, dimensions, GPS location, and favorite status.

### Metadata Enrichment

PhotoKit doesn't expose keywords, people, descriptions, albums, filenames, or edit details. These come from Photos.sqlite:

```swift
// User selects their .photoslibrary bundle (e.g., via NSOpenPanel)
let libraryURL: URL = ...

// Validate and derive database path
guard PhotosLibraryPath.validate(libraryURL).isValid,
      let dbPath = PhotosLibraryPath.databasePath(for: libraryURL)
else { return }

// Read enrichment data and apply it
let enrichment = PhotosDatabase.readEnrichment(dbPath: dbPath)
PhotosDatabase.enrich(&assets, with: enrichment)

// assets now have: originalFilename, uniformTypeIdentifier, albums,
// keywords, people, description, hasEdit, editedAt, editor
```

### File Export

Export original photo/video files to a staging directory with inline SHA-256 hashing:

```swift
let stagingDir = try PathSafety.validateStagingDir("/tmp/photo-export")
let exporter = PhotoExporter(stagingDir: stagingDir, library: library)
let response = await exporter.export(uuids: ["B84E8479-475C-4727-A7F4-B3D5E5D71923/L0/001"])

for result in response.results {
    print(result.path)   // exported file path
    print(result.sha256) // hash computed during streaming write
    print(result.size)   // file size in bytes
}
```

Files are streamed from PhotoKit to disk. SHA-256 is computed inline during the write — no second pass.

#### iCloud-only assets

When "Optimize Mac Storage" is enabled, some assets exist only in iCloud and are invisible to PhotoKit's `fetchAssets()`. For these assets, `PhotoExporter` falls back to AppleScript via Photos.app, which handles the iCloud download transparently:

```swift
let exporter = PhotoExporter(
    stagingDir: stagingDir,
    library: library,
    scriptExporter: AppleScriptRunner() // enables iCloud fallback
)
```

The fallback runs sequentially (one asset at a time) after all PhotoKit exports complete. SHA-256 is computed after export using `FileHasher`. Pass `scriptExporter: nil` to disable the fallback.

This approach is inspired by [osxphotos](https://github.com/RhetTbull/osxphotos) (MIT license) by Rhet Turnbull.

**Additional permission required:** The AppleScript fallback needs Automation permission (System Settings > Privacy & Security > Automation > ladder > Photos).

### Standalone Hashing

```swift
// Streaming hasher for incremental use
let hasher = StreamingHasher()
hasher.update(chunk1)
hasher.update(chunk2)
let hash = hasher.finalize() // hex-encoded SHA-256

// One-shot file hashing (8 MB chunks, memory-efficient)
let fileHash = try FileHasher.sha256(fileAt: fileURL)
```

## API Contract

### Provided (what LadderKit gives you)

| Protocol / Type | Purpose |
|---|---|
| `PhotoLibrary` | Asset discovery and fetch by identifier |
| `AssetHandle` | Single asset's exportable resource |
| `PhotoExporter` | Concurrent export with inline hashing |
| `ScriptExporter` | AppleScript fallback for iCloud-only assets |
| `PhotosDatabase` | Photos.sqlite enrichment reader |
| `PhotosLibraryPath` | Library bundle validation and path derivation |
| `StreamingHasher` | Incremental SHA-256 |
| `FileHasher` | One-shot file SHA-256 |
| `PathSafety` | Filename sanitization and path traversal prevention |

### Required (what your app must provide)

| Requirement | How |
|---|---|
| **Photos permission** | Call `PHPhotoLibrary.requestAuthorization(for: .readWrite)` before using `PhotoKitLibrary` |
| **Photos library path** | User selects their `.photoslibrary` bundle. Use `PhotosLibraryPath.validate()` to verify, then `databasePath(for:)` to get the sqlite path. A security-scoped bookmark from `NSOpenPanel` grants file access without Full Disk Access. |
| **Staging directory** | Provide an absolute path for exported files. Validate with `PathSafety.validateStagingDir()`. |

### Data Types

**AssetInfo** — metadata for a single photo or video:

```
identifier          String       PhotoKit local identifier (e.g., "UUID/L0/001")
uuid                String       UUID portion extracted from identifier
creationDate        Date?        when the photo was taken
kind                AssetKind    .photo (0) or .video (1)
pixelWidth          Int
pixelHeight         Int
latitude            Double?      GPS coordinates
longitude           Double?
isFavorite          Bool
originalFilename    String?      from Photos.sqlite enrichment
uniformTypeIdentifier String?    e.g., "public.heic"
hasEdit             Bool         true when both adjustment + rendered resource exist
albums              [AlbumInfo]  album membership
keywords            [String]     user-assigned keywords
people              [PersonInfo] recognized faces with names
assetDescription    String?      user-written caption (JSON key: "description")
editedAt            Date?        when the edit was made
editor              String?      editor identifier (e.g., "com.apple.photos")
```

`AssetInfo` conforms to `Codable`. The `assetDescription` field serializes as `"description"` in JSON.

**AlbumInfo** — `{ identifier: String, title: String }`

**PersonInfo** — `{ uuid: String, displayName: String }`

**ExportResult** — `{ uuid: String, path: String, size: Int64, sha256: String }`

### Testability

All external dependencies are behind protocols:

- `PhotoLibrary` — inject a mock that returns pre-configured assets
- `AssetHandle` — inject a mock that writes known data
- `ScriptExporter` — inject a mock for AppleScript fallback (or `nil` to disable)

Tests run without Photos library access, Photos permission, or network. See `Tests/PhotoExporterTests.swift` for examples.

## CLI

The CLI wraps LadderKit for use as a subprocess (used by [attic](https://github.com/tijs/attic)).

### Installing

```
make install
```

Installs to `/usr/local/bin/ladder`. Use `make install PREFIX=~/.local` for a different location.

### Usage

```bash
echo '{"uuids":["..."],"stagingDir":"/tmp/staging"}' | ladder
# or
ladder request.json
```

**Input** (`ExportRequest`):
```json
{
  "uuids": ["B84E8479-475C-4727-A7F4-B3D5E5D71923/L0/001"],
  "stagingDir": "/tmp/photo-export"
}
```

**Output** (`ExportResponse`):
```json
{
  "results": [
    {
      "uuid": "B84E8479-475C-4727-A7F4-B3D5E5D71923/L0/001",
      "path": "/tmp/photo-export/B84E8479-475C-4727_IMG_0001.HEIC",
      "size": 3158112,
      "sha256": "a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447"
    }
  ],
  "errors": [
    { "uuid": "missing-uuid", "message": "Asset not found in Photos library" }
  ]
}
```

### Required permissions

- **Photos access** — grant in System Settings > Privacy & Security > Photos
- **Full Disk Access** — may be needed depending on library location
- **Automation** (for iCloud-only assets) — grant in System Settings > Privacy & Security > Automation > ladder > Photos

## Project structure

```
Sources/
  CLI/
    Main.swift              entry point, stdin/stdout JSON protocol
  LadderKit/
    AssetInfo.swift          AssetInfo, AssetKind, AlbumInfo, PersonInfo
    PhotoLibrary.swift       PhotoLibrary protocol + PhotoKit implementation
    PhotoExporter.swift      concurrent export with inline hashing
    AppleScriptExporter.swift  iCloud-only fallback via Photos.app
    PhotosDatabase.swift     Photos.sqlite enrichment reader
    PhotosLibraryPath.swift  library bundle validation
    Hasher.swift             StreamingHasher + FileHasher
    Models.swift             ExportRequest, ExportResponse (CLI types)
    PathSafety.swift         filename sanitization, path traversal prevention
Tests/
    AssetInfoTests.swift
    PhotoExporterTests.swift
    AppleScriptExporterTests.swift
    PhotosDatabaseTests.swift
    PhotosLibraryPathTests.swift
    HasherTests.swift
    ModelsTests.swift
    PathSafetyTests.swift
```

## Testing

```
swift test
```

44 tests across 8 suites. All tests use mock implementations — no Photos library, credentials, or network required.
