import Foundation

/// Outcome of a single iCloud-lane export attempt, fed back to an adaptive
/// controller so it can tune its concurrency limit.
public enum ExportOutcome: Sendable {
    /// Export succeeded — bytes on disk.
    case success
    /// Transient failure (iCloud throttling, network blip, silent no-file).
    /// The controller should treat these as congestion signals.
    case transientFailure
    /// Permanent failure (shared-album derivative unreachable). Should be
    /// ignored by the controller — not a signal about lane health.
    case permanentFailure
}

/// Observation-only concurrency controller. The exporter polls
/// ``currentLimit()`` to decide how many iCloud tasks to run at once, and
/// reports each ``ExportOutcome`` via ``record(_:)`` so the controller can
/// tune itself.
///
/// LadderKit does not ship a concrete controller — the policy lives with the
/// consumer (e.g. AtticCore's AIMDController). Pass `nil` to run the iCloud
/// lane at the exporter's static `maxConcurrency`.
public protocol AdaptiveConcurrencyControlling: Sendable {
    /// Current concurrency cap for the iCloud lane. May change over time.
    func currentLimit() async -> Int

    /// Record the outcome of an attempt so the controller can tune its window.
    func record(_ outcome: ExportOutcome) async
}
