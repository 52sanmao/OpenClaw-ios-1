import Foundation

// MARK: - /api/jobs  — async job list

struct JobsResponseDTO: Decodable, Sendable {
    let jobs: [JobDTO]
}

struct JobDTO: Decodable, Sendable, Identifiable {
    let id: String
    let title: String?
    let state: String?         // pending | in_progress | completed | failed | stuck
    let userId: String?
    let createdAt: String?
    let startedAt: String?

    var normalizedState: String {
        (state ?? "").lowercased()
    }

    var canCancel: Bool {
        normalizedState == "pending" || normalizedState == "in_progress"
    }
}

// MARK: - /api/jobs/summary

struct JobsSummaryDTO: Decodable, Sendable {
    let total: Int
    let pending: Int
    let inProgress: Int
    let completed: Int
    let failed: Int
    let stuck: Int
}

// MARK: - /api/jobs/{id}

struct JobTransitionDTO: Decodable, Sendable, Identifiable {
    let from: String?
    let to: String?
    let timestamp: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case from, to, timestamp, reason
        case fromState = "from_state"
        case toState = "to_state"
        case at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decodeIfPresent(String.self, forKey: .from)
            ?? container.decodeIfPresent(String.self, forKey: .fromState)
        to = try container.decodeIfPresent(String.self, forKey: .to)
            ?? container.decodeIfPresent(String.self, forKey: .toState)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
            ?? container.decodeIfPresent(String.self, forKey: .at)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }

    var id: String {
        [from ?? "", to ?? "", timestamp ?? "", reason ?? ""].joined(separator: "|")
    }
}

struct JobDetailDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let description: String?
    let state: String?
    let userId: String?
    let createdAt: String?
    let startedAt: String?
    let completedAt: String?
    let elapsedSecs: Int?
    let browseUrl: String?
    let jobMode: String?
    let transitions: [JobTransitionDTO]?
    let canRestart: Bool?
    let canPrompt: Bool?
    let jobKind: String?
    let prompt: String?
    let result: String?
    let error: String?

    var normalizedState: String {
        (state ?? "").lowercased()
    }

    var canRetry: Bool {
        ["failed", "interrupted"].contains(normalizedState) && (canRestart ?? false)
    }
}

struct JobEventsResponseDTO: Decodable, Sendable {
    let jobId: String?
    let events: [JobEventDTO]
}

struct JobEventDTO: Decodable, Sendable, Identifiable {
    let id: Int?
    let eventType: String
    let data: JSONValue?
    let createdAt: String?

    var stableId: String {
        if let id { return String(id) }
        return [eventType, createdAt ?? "", dataSummary].joined(separator: "|")
    }

    var dataSummary: String {
        guard let data else { return "" }
        return String(describing: data)
    }
}

struct JobFilesListResponseDTO: Decodable, Sendable {
    let entries: [JobFileEntryDTO]
}

struct JobFileEntryDTO: Decodable, Sendable, Identifiable {
    let name: String
    let path: String
    let isDir: Bool

    enum CodingKeys: String, CodingKey {
        case name, path
        case isDir = "is_dir"
    }

    var id: String { path }
}

struct JobFileReadResponseDTO: Decodable, Sendable {
    let path: String
    let content: String
}

struct JobPromptRequestDTO: Encodable, Sendable {
    let content: String
    let done: Bool
}

struct JobPromptResponseDTO: Decodable, Sendable {
    let status: String?
    let jobId: String?
}

// MARK: - /api/gateway/status (rich system status)

struct GatewayRichStatusDTO: Decodable, Sendable {
    let version: String?
    let sseConnections: Int?
    let wsConnections: Int?
    let totalConnections: Int?
    let uptimeSecs: Int?
    let restartEnabled: Bool?
    let dailyCost: String?
    let actionsThisHour: Int?
    let modelUsage: [ModelUsageDTO]?
    let llmBackend: String?
    let llmModel: String?
    let enabledChannels: [String]?

    struct ModelUsageDTO: Decodable, Sendable {
        let model: String
        let inputTokens: Int?
        let outputTokens: Int?
        let cost: String?
    }
}

// MARK: - /api/routines/summary

struct RoutinesSummaryDTO: Decodable, Sendable {
    let total: Int
    let enabled: Int
    let disabled: Int
    let unverified: Int
    let failing: Int
    let runsToday: Int
}

// MARK: - /api/logs/level

struct LogLevelDTO: Decodable, Sendable {
    let level: String
}

// MARK: - /api/engine/missions

struct MissionsSummaryDTO: Decodable, Sendable {
    let total: Int
    let active: Int
    let paused: Int
    let completed: Int
    let failed: Int
}

struct MissionsListResponseDTO: Decodable, Sendable {
    let missions: [MissionDTO]
}

struct MissionDTO: Decodable, Sendable, Identifiable {
    let id: String
    let name: String?
    let status: String?
    let cadenceType: String?
    let cadenceDescription: String?
    let threadsToday: Int?
    let maxThreadsPerDay: Int?
    let threadCount: Int?
    let createdAt: String?
    let nextFireAt: String?

    var normalizedStatus: String {
        (status ?? "").lowercased()
    }

    var canPause: Bool {
        normalizedStatus == "active"
    }

    var canResume: Bool {
        normalizedStatus == "paused"
    }
}

struct MissionDetailResponseDTO: Decodable, Sendable {
    let mission: MissionDetailDTO?
}

struct MissionDetailDTO: Decodable, Sendable {
    let id: String
    let name: String?
    let status: String?
    let cadenceType: String?
    let cadenceDescription: String?
    let threadsToday: Int?
    let maxThreadsPerDay: Int?
    let threadCount: Int?
    let createdAt: String?
    let nextFireAt: String?
    let threads: [MissionThreadDTO]?

    var normalizedStatus: String {
        (status ?? "").lowercased()
    }

    var canPause: Bool {
        normalizedStatus == "active"
    }

    var canResume: Bool {
        normalizedStatus == "paused"
    }
}

struct MissionThreadDTO: Decodable, Sendable, Identifiable {
    let id: String
    let threadType: String?
    let stepCount: Int?
    let totalTokens: Int?
    let totalCostUsd: Double?
    let maxIterations: Int?
    let createdAt: String?
}

struct MissionFireResponseDTO: Decodable, Sendable {
    let threadId: String?
    let fired: Bool?
}
