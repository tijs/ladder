import CommonCrypto
import Foundation

/// Streaming SHA-256 hasher that can be fed chunks incrementally.
///
/// ## Safety Invariant (`@unchecked Sendable`)
/// `CC_SHA256_CTX` is a C struct and not `Sendable`. All access to `context`
/// is serialized through `lock` (an `NSLock`), ensuring no concurrent mutations.
/// Each public method acquires the lock before touching `context` and releases
/// it on return. This makes cross-isolation use safe despite the unchecked marker.
///
/// TODO: Replace with `Mutex<CC_SHA256_CTX>` (available in Swift 6 / macOS 15+)
/// once the deployment target is raised, then drop `@unchecked Sendable`.
public final class StreamingHasher: @unchecked Sendable {
    private var context = CC_SHA256_CTX()
    private let lock = NSLock()

    public init() {
        CC_SHA256_Init(&context)
    }

    /// Feed a chunk of data into the hash.
    public func update(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256_Update(&context, bytes.baseAddress, CC_LONG(data.count))
        }
    }

    /// Finalize and return the hex-encoded SHA-256 digest.
    public func finalize() -> String {
        lock.lock()
        defer { lock.unlock() }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum FileHasher {
    /// Compute SHA-256 of a file on disk (streaming, memory-efficient).
    public static func sha256(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        let hasher = StreamingHasher()
        let bufferSize = 8 * 1024 * 1024 // 8 MB chunks

        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: bufferSize)
            guard !data.isEmpty else { return false }
            hasher.update(data)
            return true
        }) {}

        return hasher.finalize()
    }
}
