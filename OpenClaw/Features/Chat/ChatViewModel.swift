import Foundation
import Observation

@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var isStreaming = false
    var isLoadingHistory = false
    var error: Error?

    private let client: GatewayClientProtocol
    private var streamTask: Task<Void, Never>?
    private var historyLoaded = false
    private var hasPendingSend = false
    private var activeThreadId: String?

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    // MARK: - Load History

    func loadHistory() async {
        guard !historyLoaded else { return }
        historyLoaded = true
        isLoadingHistory = true

        do {
            let threadId = try await resolveActiveThreadID(createIfNeeded: true)
            let history = try await client.loadChatHistory(threadId: threadId)
            if !hasPendingSend {
                messages = mapTurns(history.turns)
            }
        } catch {
            self.error = error
        }
        isLoadingHistory = false
    }

    // MARK: - Send

    func send(_ text: String) {
        hasPendingSend = true

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)
        let assistantId = assistantMessage.id

        isStreaming = true
        error = nil

        streamTask = Task {
            do {
                let threadId = try await resolveActiveThreadID(createIfNeeded: true)
                let baselineHistory = try await client.loadChatHistory(threadId: threadId)
                _ = try await client.sendThreadMessage(threadId: threadId, content: text)
                let poll = try await client.waitForThreadTurn(
                    threadId: threadId,
                    afterTurnCount: baselineHistory.turns.count,
                    timeout: 45
                )

                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[idx].content = poll.latestTurn.response ?? ""
                    messages[idx].isStreaming = false
                }
                messages = mapTurns(poll.history.turns)
                Haptics.shared.success()
            } catch is CancellationError {
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[idx].isStreaming = false
                }
            } catch {
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[idx].isStreaming = false
                    if messages[idx].content.isEmpty {
                        messages.remove(at: idx)
                    }
                }
                self.error = error
                Haptics.shared.error()
            }
            isStreaming = false
            hasPendingSend = false
        }
    }

    func reloadHistory() {
        historyLoaded = false
        hasPendingSend = false
        messages = []
        Task { await loadHistory() }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }

    private func resolveActiveThreadID(createIfNeeded: Bool) async throws -> String {
        if let activeThreadId { return activeThreadId }

        let threads = try await client.listChatThreads()
        if let thread = threads.activeThread ?? threads.assistantThread?.id ?? threads.threads.first?.id {
            activeThreadId = thread
            return thread
        }

        guard createIfNeeded else {
            throw GatewayError.invalidResponse
        }
        let created = try await client.createChatThread()
        activeThreadId = created.id
        return created.id
    }

    private func mapTurns(_ turns: [ChatThreadTurn]) -> [ChatMessage] {
        var mapped: [ChatMessage] = []
        let formatter = ISO8601DateFormatter()
        for turn in turns {
            let timestamp = turn.startedAt.flatMap(formatter.date(from:)) ?? Date()
            let user = turn.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !user.isEmpty {
                mapped.append(ChatMessage(role: .user, content: user, timestamp: timestamp))
            }
            let reply = (turn.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !reply.isEmpty {
                mapped.append(ChatMessage(role: .assistant, content: reply, timestamp: timestamp))
            }
        }
        return mapped
    }
}
