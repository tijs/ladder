# Changelog

## 0.1.0

Initial release.

- Export original photo/video files from the iCloud Photos library via PhotoKit
- Batch processing: accepts multiple UUIDs per invocation
- JSON protocol over stdin/stdout for integration with attic
- SHA-256 checksums computed during export
- Staging directory for exported files with configurable path
- Makefile with install/uninstall targets
