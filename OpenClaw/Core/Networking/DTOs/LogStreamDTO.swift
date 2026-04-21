import Foundation

/// A single log entry from the SSE `/api/logs/events` stream.
struct LogStreamEntry: Decodable, Sendable, Identifiable {
    let timestamp: String
    let level: String
    let target: String
    let message: String

    var id: String { "\(timestamp)-\(target)-\(message.hashValue)" }

    /// Parsed level normalized to lowercase for filtering.
    var normalizedLevel: String { level.lowercased() }

    /// Extract HH:mm:ss from the RFC 3339 timestamp.
    var timeDisplay: String {
        if let tIndex = timestamp.firstIndex(of: "T") {
            let after = timestamp.index(after: tIndex)
            return String(timestamp[after...].prefix(8))
        }
        return String(timestamp.prefix(8))
    }
}
