import Foundation

struct CronRunsPage: Sendable {
    let runs: [CronRun]
    let hasMore: Bool
    let total: Int?
}

protocol CronDetailRepository: Sendable {
    func fetchRuns(jobId: String, limit: Int, offset: Int) async throws -> CronRunsPage

    func fetchSessionTrace(sessionKey: String, limit: Int) async throws -> SessionTrace
    func triggerRun(jobId: String) async throws
    func setEnabled(jobId: String, enabled: Bool) async throws
    func deleteRoutine(jobId: String) async throws
}

final class RemoteCronDetailRepository: CronDetailRepository {
    private let client: GatewayClientProtocol

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    func fetchRuns(jobId: String, limit: Int, offset: Int) async throws -> CronRunsPage {
        let dto = try await client.loadRoutineRuns(jobId: jobId)
        let runs = dto.runs.map(CronRun.init)
        let sliced = Array(runs.dropFirst(offset).prefix(limit))
        return CronRunsPage(runs: sliced, hasMore: offset + sliced.count < runs.count, total: runs.count)
    }

    func fetchSessionTrace(sessionKey: String, limit: Int) async throws -> SessionTrace {
        let body = SessionHistoryToolRequest(args: .init(sessionKey: sessionKey, limit: limit, includeTools: true))
        let dto: SessionHistoryDTO = try await client.invoke(body)
        return TraceStep.from(dto: dto)
    }

    func triggerRun(jobId: String) async throws {
        try await client.triggerRoutine(jobId: jobId, mode: "force")
    }

    func setEnabled(jobId: String, enabled: Bool) async throws {
        try await client.setRoutineEnabled(jobId: jobId, enabled: enabled)
    }

    func deleteRoutine(jobId: String) async throws {
        let escaped = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        try await client.statsDeleteVoid("api/routines/\(escaped)")
    }
}
