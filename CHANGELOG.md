# Changelog

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
