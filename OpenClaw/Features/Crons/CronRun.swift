import Foundation

struct CronRun: Sendable, Identifiable {
    /// Use the entry timestamp as ID — unique per run entry.
    let id: String

    let jobId: String
    let status: CronJob.RunStatus
    let summary: String?
    let runAt: Date
    let duration: TimeInterval
    let model: String?
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    /// Full session key for sessions_history API (e.g. "agent:orchestrator:subagent:UUID")
    let sessionKey: String?
    /// Short session ID (UUID only)
    let sessionId: String?

    var durationFormatted: String {
        let seconds = Int(duration / 1000)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        return "\(minutes)m \(remaining)s"
    }

    var runAtFormatted: String {
        Formatters.relativeString(for: runAt)
    }

    var runAtAbsolute: String {
        Formatters.absoluteString(for: runAt)
    }

    init(dto: CronRunDTO) {
        id = "\(dto.ts)"
        jobId = dto.jobId
        summary = dto.summary
        runAt = Date(timeIntervalSince1970: Double(dto.runAtMs) / 1000)
        duration = Double(dto.durationMs)
        model = dto.model
        inputTokens = dto.usage?.inputTokens ?? 0
        outputTokens = dto.usage?.outputTokens ?? 0
        totalTokens = dto.usage?.totalTokens ?? 0
        sessionKey = dto.sessionKey
        sessionId = dto.sessionId

        switch dto.status {
        case "ok":    status = .succeeded
        case "error": status = .failed
        default:      status = .unknown
        }
    }

    init(dto: RoutineRunDTO) {
        id = dto.id
        jobId = dto.jobId ?? ""
        summary = dto.resultSummary
        runAt = Self.date(from: dto.startedAt ?? dto.completedAt) ?? Date.distantPast
        duration = Self.durationMs(startedAt: dto.startedAt, completedAt: dto.completedAt)
        model = nil
        inputTokens = 0
        outputTokens = 0
        totalTokens = dto.tokensUsed ?? 0
        sessionKey = nil
        sessionId = nil

        switch dto.status?.lowercased() {
        case "ok", "success", "succeeded": status = .succeeded
        case "error", "failed", "failure": status = .failed
        default: status = .unknown
        }
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds > 10_000_000_000 {
            return Date(timeIntervalSince1970: seconds / 1000)
        }
        if let seconds = Double(value) {
            return Date(timeIntervalSince1970: seconds)
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func durationMs(startedAt: String?, completedAt: String?) -> TimeInterval {
        guard let startedAt, let completedAt else { return 0 }
        guard let start = date(from: startedAt), let end = date(from: completedAt) else { return 0 }
        return max(0, end.timeIntervalSince(start) * 1000)
    }
}
