import Foundation
import Observation

@Observable
@MainActor
final class SessionsViewModel {
    var sessions: [SessionEntry] = []
    var isLoading = false
    var error: Error?

    private let repository: SessionRepository

    var chatSessions: [SessionEntry] {
        sessions
            .filter { if case .subagent = $0.kind { return false } else { return true } }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    var subagents: [SessionEntry] {
        sessions
            .filter { if case .subagent = $0.kind { return true } else { return false } }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    init(repository: SessionRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        AppLogStore.shared.append("SessionsViewModel: 开始刷新会话列表")
        do {
            sessions = try await repository.fetchSessions(limit: 500)
            error = nil
            AppLogStore.shared.append("SessionsViewModel: 会话列表刷新完成 count=\(sessions.count) chats=\(chatSessions.count) subagents=\(subagents.count)")
        } catch {
            self.error = error
            AppLogStore.shared.append("SessionsViewModel: 会话列表刷新失败 error=\(error.localizedDescription)")
        }
        isLoading = false
    }
}
