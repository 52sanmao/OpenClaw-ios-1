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
    private let sessionKey = "agent:orchestrator:main"
    private var streamTask: Task<Void, Never>?
    private var historyLoaded = false

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    // MARK: - Load History

    func loadHistory() async {
        guard !historyLoaded else { return }
        historyLoaded = true
        isLoadingHistory = true

        do {
            let body = SessionHistoryToolRequest(args: .init(sessionKey: sessionKey, limit: 50, includeTools: false))
            let dto: SessionHistoryDTO = try await client.invoke(body)

            var loaded: [ChatMessage] = []
            for message in dto.messages {
                switch message.role {
                case "user":
                    let text = (message.content ?? []).compactMap(\.text).joined(separator: "\n")
                    if !text.isEmpty {
                        loaded.append(ChatMessage(role: .user, content: text))
                    }
                case "assistant":
                    let text = (message.content ?? [])
                        .filter { $0.type == "text" }
                        .compactMap(\.text)
                        .joined(separator: "\n")
                    if !text.isEmpty {
                        loaded.append(ChatMessage(role: .assistant, content: text))
                    }
                default:
                    break
                }
            }

            // Only set if no new messages were sent while loading
            if messages.isEmpty {
                messages = loaded
            }
        } catch {
            // Non-fatal — chat still works without history
            self.error = error
        }
        isLoadingHistory = false
    }

    // MARK: - Send

    func send(_ text: String) {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        isStreaming = true
        error = nil

        streamTask = Task {
            do {
                let stream = client.streamChat(message: text, sessionKey: sessionKey)
                for try await delta in stream {
                    messages[assistantIndex].content += delta
                }
                messages[assistantIndex].isStreaming = false
                Haptics.shared.success()
            } catch is CancellationError {
                messages[assistantIndex].isStreaming = false
            } catch {
                messages[assistantIndex].isStreaming = false
                if messages[assistantIndex].content.isEmpty {
                    messages.remove(at: assistantIndex)
                }
                self.error = error
                Haptics.shared.error()
            }
            isStreaming = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }
}
