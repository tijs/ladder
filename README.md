<p align="center">
  <img src="ladder-logo.png" width="128" alt="ladder logo">
</p>

# ladder

A macOS CLI tool that exports original photos and videos from the macOS Photos library using PhotoKit.

## What it does

ladder takes a JSON request on stdin (or from a file argument), exports the requested assets from the Photos library to a staging directory, computes a SHA-256 hash for each file during export, and writes a JSON response to stdout. It is designed to be called as a subprocess by [attic](https://github.com/tijs/attic), the Deno/TypeScript component of the photo-cloud backup system.

## How it works

1. Reads a JSON `ExportRequest` from stdin (or from a file path passed as the first argument)
2. Requests Photos library authorization via PhotoKit
3. Fetches assets by their local identifiers (UUIDs)
4. Exports each asset's original resource to the staging directory with bounded concurrency (default: 6)
5. Computes SHA-256 inline while streaming data to disk (no second pass over the file)
6. Writes a JSON `ExportResponse` to stdout

## Installing

Requires macOS 13+ and Swift 5.9+.

```
make install
```

This builds a release binary and installs it to `/usr/local/bin/ladder`. To install elsewhere:

```
make install PREFIX=~/.local
```

To uninstall:

```
make uninstall
```

## Usage

### Input (ExportRequest)

```json
{
  "uuids": [
    "B84E8479-475C-4727-A7F4-B3D5E5D71923/L0/001",
    "3FA8GH5M-BMMH-H123-ABCD-1234567890AB/L0/001"
  ],
  "stagingDir": "/tmp/photo-export"
}
```

- `uuids` -- Photos library local identifiers to export
- `stagingDir` -- absolute path where exported files will be written (must not be inside system directories like `/System`, `/Library`, `/usr`, etc.)

### Running

```bash
# From stdin
echo '{"uuids":["..."],"stagingDir":"/tmp/staging"}' | .build/release/ladder

# From a file
.build/release/ladder request.json
```

### Output (ExportResponse)

Written to stdout:

```json
{
  "errors": [
    {
      "message": "Asset not found in Photos library",
      "uuid": "missing-uuid"
    }
  ],
  "results": [
    {
      "path": "/tmp/photo-export/B84E8479-475C-4727_IMG_0001.HEIC",
      "sha256": "a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447",
      "size": 3158112,
      "uuid": "B84E8479-475C-4727-A7F4-B3D5E5D71923/L0/001"
    }
  ]
}
```

Each result includes the file path, size in bytes, and SHA-256 hash. Assets that could not be found or exported appear in the `errors` array.

## Required permissions

- **Photos access** -- ladder requests read/write authorization on launch. Grant access in System Settings > Privacy & Security > Photos.
- **Full Disk Access** -- may be required depending on how the Photos library is stored. Grant in System Settings > Privacy & Security > Full Disk Access.

## Testing

```
swift test
```

Tests use protocol-based dependency injection (`PhotoLibrary` / `AssetHandle` protocols) with mock implementations, so they run without Photos library access.

## Project structure

```
Sources/
  CLI/
    Main.swift           -- entry point, stdin parsing, authorization
  LadderKit/
    Models.swift         -- ExportRequest, ExportResponse, ExportResult, ExportError
    PhotoExporter.swift  -- concurrent export orchestration
    PhotoLibrary.swift   -- PhotoKit abstraction (protocol + real implementation)
    Hasher.swift         -- streaming SHA-256 (inline with export)
    PathSafety.swift     -- filename sanitization and path traversal prevention
Tests/
    ModelsTests.swift
    PhotoExporterTests.swift
    HasherTests.swift
    PathSafetyTests.swift
```

## How it fits with attic

In the photo-cloud system, **attic** (Deno/TypeScript) is the orchestrator that determines which photos need backing up and manages cloud storage. It spawns **ladder** as a subprocess to handle the macOS-specific part: accessing the Photos library via PhotoKit and exporting original files to a staging directory. attic sends a JSON request with the asset UUIDs, ladder exports them and reports back with file paths and hashes, and attic takes it from there.
