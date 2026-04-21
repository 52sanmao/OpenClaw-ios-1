import Foundation

struct SessionEntry: Sendable, Identifiable {
    let id: String
    let kind: Kind
    let displayName: String
    let model: String?
    let status: SessionStatus
    let updatedAt: Date?
    let startedAt: Date?
    let totalTokens: Int
    let contextTokens: Int
    let costUsd: Double
    let childSessionCount: Int
    let traceLookupKey: String
    let channel: String?
    let threadType: String?

    var contextUsage: Double {
        guard contextTokens > 0 else { return 0 }
        return min(Double(totalTokens) / Double(contextTokens), 1.0)
    }

    enum Kind: Sendable, Equatable {
        case main
        case cron(jobId: String)
        case subagent
    }

    enum SessionStatus: Sendable {
        case running, done, unknown
    }

    var updatedAtFormatted: String {
        guard let updatedAt else { return "—" }
        return Formatters.relativeString(for: updatedAt)
    }

    var startedAtFormatted: String {
        guard let startedAt else { return "—" }
        return Formatters.absoluteString(for: startedAt)
    }

    var contextBadges: [String] {
        var badges: [String] = []
        if let threadType, !threadType.isEmpty, threadType.lowercased() != "assistant" {
            badges.append(threadType)
        }
        if let channel, !channel.isEmpty, !badges.contains(where: { $0.caseInsensitiveCompare(channel) == .orderedSame }) {
            badges.append(channel)
        }
        return badges
    }

    var isReadOnlyChannel: Bool {
        guard let channel else { return false }
        return !["gateway", "routine", "heartbeat"].contains(channel.lowercased())
    }

    init(
        id: String,
        kind: Kind,
        displayName: String,
        model: String?,
        status: SessionStatus,
        updatedAt: Date?,
        startedAt: Date?,
        totalTokens: Int,
        contextTokens: Int,
        costUsd: Double,
        childSessionCount: Int,
        traceLookupKey: String? = nil,
        channel: String? = nil,
        threadType: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.model = model
        self.status = status
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.totalTokens = totalTokens
        self.contextTokens = contextTokens
        self.costUsd = costUsd
        self.childSessionCount = childSessionCount
        self.traceLookupKey = traceLookupKey ?? id
        self.channel = channel
        self.threadType = threadType
    }

    @MainActor init(dto: SessionListDTO) {
        id = dto.key
        displayName = dto.displayName ?? dto.label ?? dto.key
        model = dto.model
        totalTokens = dto.totalTokens ?? 0
        contextTokens = dto.contextTokens ?? 0
        costUsd = dto.estimatedCostUsd ?? 0
        childSessionCount = dto.childSessions?.count ?? 0
        updatedAt = dto.updatedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        startedAt = dto.startedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        traceLookupKey = dto.sessionId ?? dto.key
        channel = dto.channel
        threadType = nil

        switch dto.status {
        case "running": status = .running
        case "done":    status = .done
        default:        status = .unknown
        }

        if id == SessionKeys.main {
            kind = .main
        } else if id.hasPrefix(SessionKeys.cronPrefix) {
            let jobId: String
            if id.contains(":run:") {
                let withoutPrefix = String(id.dropFirst(SessionKeys.cronPrefix.count))
                jobId = String(withoutPrefix.split(separator: ":").first ?? "")
            } else {
                jobId = String(id.dropFirst(SessionKeys.cronPrefix.count))
            }
            kind = .cron(jobId: jobId)
        } else if id.hasPrefix(SessionKeys.subagentPrefix) {
            kind = .subagent
        } else {
            kind = .main
        }
    }
}
