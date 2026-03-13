# Ladder

Swift PhotoKit export helper for iCloud Photos backup. Part of the photo-cloud system (companion: [attic](https://github.com/tijs/attic)).

## Commands

```bash
swift build -c release | xcsift    # Build release binary
swift test | xcsift                 # Run tests (19 tests)
swiftlint --fix                    # Auto-fix lint issues
```

## Architecture

- **LadderKit** (library): `PhotoExporter`, `StreamingHasher`, `FileHasher`, model types, path safety
- **CLI** (executable): Reads JSON request from stdin, calls PhotoExporter, writes JSON response to stdout

## Conventions

- Use `debugPrint()` instead of `print()` (stripped by compiler in release)
- Dependencies are injected for testability — no real PhotoKit calls in tests
- `StreamingHasher` uses `@unchecked Sendable` with `NSLock` — documented safety invariant in `Hasher.swift`. TODO: migrate to `Mutex<CC_SHA256_CTX>` when targeting macOS 15+
- Pipe all xcodebuild/swift commands through `xcsift` for clean output
- Files should stay under 500 lines
