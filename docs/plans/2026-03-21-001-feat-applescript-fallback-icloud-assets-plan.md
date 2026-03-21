---
title: "feat: AppleScript fallback for iCloud-only assets"
type: feat
status: active
date: 2026-03-21
---

# AppleScript fallback for iCloud-only assets

## Overview

When "Optimize Mac Storage" is enabled, ~17% of assets (6,400 of 37,305) are
iCloud-only. PhotoKit's `PHAsset.fetchAssets(withLocalIdentifiers:)` cannot find
these assets at all — they're invisible to the API even with
`isNetworkAccessAllowed = true`. This means ladder currently reports them as
"Asset not found in Photos library" errors, making it impossible to back up a
complete library.

The fix: when PhotoKit can't find a UUID, fall back to AppleScript via
Photos.app, which handles iCloud downloads transparently. Inspired by
[osxphotos](https://github.com/RhetTbull/osxphotos) (MIT license) which uses
this exact mechanism.

## Problem Statement

PhotoKit has two layers: **enumeration** (finding assets by identifier) and
**export** (downloading data from an asset). The iCloud-only problem is at the
enumeration layer — `PHAsset.fetchAssets()` simply doesn't return these assets.
Setting `isNetworkAccessAllowed = true` on the export options has no effect
because there's no `PHAsset` object to export from.

Photos.app, however, can access ALL assets regardless of cloud state. Its
AppleScript `export` command triggers an iCloud download transparently and writes
the original file to disk.

## Proposed Solution

Add an `AppleScriptExporter` to LadderKit that `PhotoExporter` delegates to when
PhotoKit can't find a UUID. The fallback:

1. Runs only for UUIDs that `fetchAssets()` couldn't find (not for export
   failures)
2. Exports one asset at a time via AppleScript (network-bound, serialization
   avoids Photos.app contention)
3. Computes SHA-256 after export using existing `FileHasher`
4. Returns the same `ExportResult` format — attic sees no difference

```applescript
tell application "Photos"
    set thePic to media item id "8A3B1C2D-4E5F-6789-ABCD-EF0123456789"
    export {thePic} to POSIX file "/path/to/staging/uuid_subdir" with using originals
end tell
```

## Technical Considerations

### CLI and GUI dual-use

The fallback lives in **LadderKit** (the shared library), not in the CLI target
or in attic. This means both consumers get it automatically:

- **CLI** (attic subprocess): `PhotoExporter.export(uuids:)` is called from
  `Main.swift`. The AppleScript fallback runs in the same process via
  `Process()` + `osascript`. No changes needed in attic — the `ExportResponse`
  format is unchanged.
- **Menu bar app** (direct LadderKit import): calls `PhotoExporter.export(uuids:)`
  directly as a Swift package. Same fallback triggers, same behavior.

The `ScriptExporter` protocol allows each consumer to provide a custom
implementation if needed. For example, the menu bar app could use
`NSAppleScript` (in-process, no subprocess overhead) instead of the default
`osascript`-via-`Process()`. But the default works for both contexts.

**Automation permission** is per-binary: the CLI binary and the menu bar app
each need their own grant. The menu bar app will prompt automatically on first
use (standard macOS behavior for GUI apps). The CLI needs a one-time interactive
grant, documented in `attic init`.

### UUID format

Attic sends identifiers in PhotoKit format: `UUID/L0/001`. AppleScript's
`media item id` expects the bare UUID only. Ladder must strip the `/L0/001`
suffix before passing to AppleScript. The bare UUID is already extracted in
`AssetInfo.swift` — reuse that logic.

### SHA-256

The normal PhotoKit path uses `StreamingHasher` (inline during data stream). For
AppleScript exports, the file is written by Photos.app — we hash it after using
`FileHasher.sha256(fileAt:)` which already exists in `Hasher.swift`. This means
an extra read pass over the file, but iCloud-only assets are already
network-bound so the disk I/O overhead is negligible.

### Exported filename discovery

AppleScript `export` writes files to a directory using Photos.app's internal
naming (e.g., `IMG_1234.HEIC`). We don't control the filename. The approach:

1. Create a per-asset temp subdirectory inside staging dir
2. Run AppleScript export to that subdirectory
3. Find the single file that appeared (glob for `*` in the subdir)
4. Compute size and SHA-256
5. Move to final staging path using `PathSafety.safeDestination()` naming

### Live Photos

AppleScript `export ... with using originals` may produce two files for Live
Photos (HEIC + MOV). For the initial implementation: take the photo component
only (match by image extension). The video component of Live Photos is a future
enhancement.

### Concurrency

AppleScript exports are serialized — one at a time. Photos.app serializes Apple
Events internally, and concurrent requests cause unpredictable behavior.
`PhotoExporter` continues to use `maxConcurrency: 6` for PhotoKit assets. The
AppleScript fallback runs sequentially after all PhotoKit exports complete.

### Photos.app lifecycle

- `tell application "Photos"` launches Photos.app if not running — this is
  acceptable since the user is already using their Photos library
- Ladder does NOT quit Photos.app after finishing — leave lifecycle to the user
- If Photos.app shows a modal dialog (update, repair), the AppleScript will
  time out — this is reported as an error, not a hang

### Disk space

Before starting AppleScript exports, check available disk space:
- Minimum threshold: 2 GB free
- If below threshold: skip remaining iCloud-only assets with a clear message,
  continue with local-only assets
- Check once before the AppleScript batch, not per-asset (disk space changes
  are gradual)

Photos.app manages its own iCloud cache and will evict old downloads when space
is low. After attic uploads and deletes staged files, the disk pressure is
temporary.

### macOS permissions

AppleScript to Photos.app requires **Automation permission** (System Settings >
Privacy & Security > Automation > ladder > Photos). This is separate from the
existing Photos library access and Full Disk Access permissions.

- First AppleScript call triggers a system permission prompt
- For unattended LaunchAgent runs: user must pre-grant this permission
  interactively once
- The `attic init` command should mention this in its setup instructions
- If permission is denied, the AppleScript fails with error -1743 — report this
  as a clear error with instructions to grant permission

### Pre-flight permission check

Before starting the backup, ladder should verify that required permissions are
available and give the user clear instructions if they're not. This avoids
wasting time exporting local assets only to fail on iCloud-only ones later.

**Check at startup (in `PhotoExporter` or caller):**

1. **Photos library access** — already checked in `Main.swift` via
   `PHPhotoLibrary.requestAuthorization()`. If denied, exit with instructions.
2. **Automation permission** (only when `scriptExporter` is non-nil) — run a
   lightweight AppleScript probe before the real export:
   ```applescript
   tell application "Photos" to return "ok"
   ```
   If this returns error -1743, the user hasn't granted Automation permission.
   Report a clear, actionable error **before any export work begins**:
   ```
   ladder: Automation permission required for iCloud-only assets.
   Grant access: System Settings > Privacy & Security > Automation > ladder > Photos
   ```
   Then exit with a non-zero code so attic can surface the message.

**Design:**

- Add a `public func checkPermissions() async throws` method to
  `AppleScriptRunner` (and the `ScriptExporter` protocol as optional with a
  default no-op extension).
- `PhotoExporter.export()` calls `scriptExporter?.checkPermissions()` before
  processing any assets. If it throws, all UUIDs are reported as errors with the
  permission message — no partial work is done.
- The CLI (`Main.swift`) can also call the check before creating the exporter to
  fail fast with a user-friendly message.
- The menu bar app can call the check during its setup flow and present a native
  macOS dialog guiding the user to System Settings.

**Why pre-flight, not fail-on-first-use:**

- Avoids exporting 40 local assets successfully, then failing on the first
  iCloud-only one with a confusing Apple Event error
- Gives the user one clear instruction upfront instead of a mid-backup error
- For unattended runs (LaunchAgent), the backup fails immediately with an
  actionable log message rather than producing a partial result

### Timeout

Per-asset timeout for AppleScript exports: use the existing `timeoutForBytes`
formula (5 min base + 1 min per 100 MB). Ladder doesn't know the file size
upfront for iCloud-only assets, so use a generous default of 10 minutes per
asset. If the `osascript` process exceeds this, kill it and report the asset as
failed.

## Acceptance Criteria

- [ ] iCloud-only assets that PhotoKit can't find are exported via AppleScript
      fallback
- [ ] `ExportResponse` includes successful results for AppleScript-exported
      assets (same format as PhotoKit exports)
- [ ] AppleScript exports are serialized (one at a time)
- [ ] SHA-256 is computed for AppleScript-exported files
- [ ] Disk space check before starting AppleScript exports (skip if < 2 GB)
- [ ] Pre-flight permission check before any export work begins
- [ ] Clear, actionable error message when Automation permission is missing
- [ ] Per-asset timeout kills hung `osascript` processes
- [ ] Existing PhotoKit export path is completely unchanged
- [ ] All new code is behind protocols for testability and dual-use (CLI + GUI)
- [ ] `ScriptExporter` protocol allows custom implementations per consumer
- [ ] osxphotos credited in README
- [ ] Tests cover: fallback triggers, script failure, timeout, disk space check,
      filename discovery, UUID format stripping, permission probe

## Implementation

### Files to create

| File | Purpose |
|------|---------|
| `Sources/LadderKit/AppleScriptExporter.swift` | Protocol + real implementation for AppleScript export |
| `Tests/AppleScriptExporterTests.swift` | Tests with mock script runner |

### Files to modify

| File | Change |
|------|--------|
| `Sources/LadderKit/PhotoExporter.swift` | After PhotoKit fetch, pass missing UUIDs to AppleScriptExporter |
| `Sources/LadderKit/Models.swift` | Add optional `exportMethod` field to `ExportResult` (debugging aid) |
| `README.md` | Document fallback behavior, credit osxphotos |

### `AppleScriptExporter.swift` design

```
protocol ScriptExporter: Sendable
    func exportAsset(uuid: String, to directory: URL) async throws -> URL

struct AppleScriptRunner: ScriptExporter
    - Strips /L0/001 suffix from UUID
    - Creates per-asset temp subdirectory
    - Runs osascript via Process()
    - Discovers exported file
    - Returns file URL

    - Timeout: kills Process after deadline
    - Disk space: checked before first export in batch
```

Key design: `ScriptExporter` protocol allows injection of a mock for testing
**and** alternative implementations per consumer:
- CLI: uses default `AppleScriptRunner` (runs `osascript` via `Process()`)
- Menu bar app: can inject an `NSAppleScript`-based implementation (optional,
  the default also works)
- Tests: inject a mock that returns preconfigured files

`PhotoExporter` accepts an optional `ScriptExporter` parameter (default:
`AppleScriptRunner()`).

### `PhotoExporter.export()` flow change

```
Current:
  1. fetchAssets(uuids) → found + missing
  2. Report missing as errors immediately
  3. Export found via PhotoKit (concurrent)
  4. Return results + errors

New:
  0. Pre-flight: scriptExporter?.checkPermissions() — fail fast if denied
  1. fetchAssets(uuids) → found + missing
  2. Export found via PhotoKit (concurrent, unchanged)
  3. For missing UUIDs: try AppleScript fallback (sequential)
     a. Check disk space (skip all if < 2 GB)
     b. For each missing UUID:
        - Create temp subdir
        - Run osascript with timeout
        - Discover exported file
        - Hash with FileHasher
        - Move to staging path
        - Build ExportResult
     c. Report failures as errors
  4. Return combined results + errors
```

PhotoKit exports run first (fast, concurrent). AppleScript exports run second
(slow, sequential). This way the fast path is never blocked by iCloud downloads.

### AppleScript command

```applescript
tell application "Photos"
    set thePic to media item id "{bare_uuid}"
    export {thePic} to POSIX file "{temp_subdir}" with using originals
end tell
```

Executed via:
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
process.arguments = ["-e", script]
```

### Error handling

| Scenario | Behavior |
|----------|----------|
| Automation permission denied (-1743) | Error: "Grant Automation permission for ladder to control Photos in System Settings" |
| Photos.app modal dialog (blocks export) | Timeout fires, kill process, report as failed |
| Asset not found in Photos.app either | Error: "Asset not found in Photos library or Photos.app" |
| iCloud download fails (network error) | Error from osascript, reported as export failure |
| Disk space < 2 GB | Skip all remaining AppleScript exports, log warning |
| Export produces no file | Error: "AppleScript export produced no file" |
| Export produces multiple files (Live Photo) | Take image file, ignore video component |

## Verification

1. `swift build | xcsift` — compiles
2. `swift test | xcsift` — all existing + new tests pass
3. Manual: run ladder with a known iCloud-only UUID, verify AppleScript fallback
   triggers and produces correct output
4. Manual: run `attic backup --limit 5` with iCloud-only assets in the batch,
   verify end-to-end flow

## Sources

- [osxphotos](https://github.com/RhetTbull/osxphotos) (MIT) — AppleScript
  export pattern for iCloud-only assets
- `PhotoExporter.swift:22-24` — current "Asset not found" error generation
- `PhotoLibrary.swift:39-54` — `fetchAssets()` where iCloud-only assets are
  invisible
- `Hasher.swift:41-58` — `FileHasher.sha256(fileAt:)` for post-export hashing
