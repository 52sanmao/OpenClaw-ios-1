import Foundation
import os

private let logger = Logger(subsystem: "co.uk.appwebdev.openclaw", category: "SessionRepo")

protocol SessionRepository: Sendable {
    @MainActor func fetchSessions(limit: Int) async throws -> [SessionEntry]
    func fetchTrace(sessionKey: String, limit: Int) async throws -> SessionTrace
}

final class RemoteSessionRepository: SessionRepository {
    private let client: GatewayClientProtocol

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    @MainActor
    func fetchSessions(limit: Int) async throws -> [SessionEntry] {
        let body = SessionListToolRequest(args: .init(limit: limit))
        do {
            let response: SessionListResponseDTO = try await client.invoke(body)
            logger.debug("fetchSessions OK — \(response.sessions.count) sessions")

            // Debug: log account config used for session classification
            let account = AppConstants.account
            logger.debug("Active account: \(account?.name ?? "nil"), agentId: \(account?.agentId ?? "nil"), sessionKeyMain: \(SessionKeys.main)")

            let entries = response.sessions.map { dto in
                let entry = SessionEntry(dto: dto)
                logger.debug("Session \(dto.key) → kind: \(String(describing: entry.kind))")
                return entry
            }

            let mainCount = entries.filter { if case .main = $0.kind { return true } else { return false } }.count
            let subCount = entries.filter { if case .subagent = $0.kind { return true } else { return false } }.count
            logger.debug("Classification: \(mainCount) main, \(subCount) subagent, \(entries.count) total")

            return entries.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        } catch {
            logger.error("fetchSessions FAILED — \(error.localizedDescription)")
            if let gwError = error as? GatewayError {
                logger.error("GatewayError: \(gwError.errorDescription ?? "unknown")")
            }
            throw error
        }
    }

    func fetchTrace(sessionKey: String, limit: Int) async throws -> SessionTrace {
        let body = SessionHistoryToolRequest(args: .init(sessionKey: sessionKey, limit: limit, includeTools: true))
        let dto: SessionHistoryDTO = try await client.invoke(body)
        return TraceStep.from(dto: dto)
    }
}
