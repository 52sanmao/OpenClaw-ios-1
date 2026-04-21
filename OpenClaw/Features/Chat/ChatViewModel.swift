import Foundation
import Observation

@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var isStreaming = false
    var isLoadingHistory = false
    var error: Error?
    var activeThreadTitle: String?
    var activeThreadChannel: String?
    var activeThreadType: String?
    var activeThreadState: String?
    private(set) var activeThreadId: String?

    var threads: [ChatThreadInfo] = []
    var isLoadingThreads = false

    private let client: GatewayClientProtocol
    private var streamTask: Task<Void, Never>?
    private var historyLoaded = false
    private var hasPendingSend = false

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    var navigationTitle: String {
        if let title = activeThreadTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return "灵控"
    }

    var threadBadges: [String] {
        var badges: [String] = []
        if let type = normalizedLabel(activeThreadType), type.lowercased() != "assistant" {
            badges.append(type)
        }
        if let channel = normalizedLabel(activeThreadChannel), !badges.contains(where: { $0.caseInsensitiveCompare(channel) == .orderedSame }) {
            badges.append(channel)
        }
        if let state = stateDisplayText(activeThreadState), !badges.contains(where: { $0 == state }) {
            badges.append(state)
        }
        return badges
    }

    var isReadOnlyThread: Bool {
        let channel = (activeThreadChannel ?? "gateway").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !channel.isEmpty && !["gateway", "routine", "heartbeat"].contains(channel)
    }

    var readOnlyReason: String? {
        guard isReadOnlyThread else { return nil }
        return "该线程来自 \((normalizedLabel(activeThreadChannel) ?? "external")) 频道，只能查看，不能继续发送。"
    }

    var composerPlaceholder: String {
        readOnlyReason == nil ? "输入消息…" : "当前线程不可回复"
    }

    func loadHistory() async {
        guard !historyLoaded else { return }
        historyLoaded = true
        isLoadingHistory = true

        do {
            let threadId = try await resolveActiveThreadID(createIfNeeded: true)
            await refreshThreadMetadata(threadId: threadId)
            let history = try await client.loadChatHistory(threadId: threadId)
            if !hasPendingSend {
                messages = mapHistory(history)
            }
            error = nil
        } catch {
            self.error = error
        }
        isLoadingHistory = false
    }

    func send(_ text: String) {
        guard !isReadOnlyThread else { return }
        hasPendingSend = true

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true, timestamp: userMessage.timestamp, stateText: "处理中")
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
                await refreshThreadMetadata(threadId: threadId)

                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[idx].content = poll.latestTurn.response ?? ""
                    messages[idx].isStreaming = false
                    messages[idx].stateText = stateDisplayText(poll.latestTurn.state)
                }
                messages = mergeHistory(
                    poll.history,
                    pendingUserText: text,
                    pendingUserTimestamp: userMessage.timestamp,
                    assistantFallback: poll.latestTurn.response
                )
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

    func loadThreads() async {
        isLoadingThreads = true
        do {
            let list = try await client.listChatThreads()
            threads = [list.assistantThread].compactMap { $0 } + list.threads
        } catch {
            threads = []
        }
        isLoadingThreads = false
    }

    func switchToThread(_ thread: ChatThreadInfo) {
        activeThreadId = thread.id
        applyThreadMetadata(thread)
        reloadHistory()
    }

    func createNewThread() {
        activeThreadId = nil
        activeThreadTitle = nil
        activeThreadChannel = nil
        activeThreadType = nil
        activeThreadState = nil
        reloadHistory()
    }

    private func resolveActiveThreadID(createIfNeeded: Bool) async throws -> String {
        if let activeThreadId { return activeThreadId }

        let threads = try await client.listChatThreads()
        let availableThreads = [threads.assistantThread].compactMap { $0 } + threads.threads

        if let active = threads.activeThread,
           let thread = availableThreads.first(where: { $0.id == active }) {
            applyThreadMetadata(thread)
            return thread.id
        }

        if let assistant = threads.assistantThread {
            applyThreadMetadata(assistant)
            return assistant.id
        }

        if let first = threads.threads.first {
            applyThreadMetadata(first)
            return first.id
        }

        guard createIfNeeded else {
            throw GatewayError.invalidResponse
        }
        let created = try await client.createChatThread()
        applyThreadMetadata(created)
        return created.id
    }

    private func refreshThreadMetadata(threadId: String) async {
        do {
            let threads = try await client.listChatThreads()
            let availableThreads = [threads.assistantThread].compactMap { $0 } + threads.threads
            if let thread = availableThreads.first(where: { $0.id == threadId }) {
                applyThreadMetadata(thread)
            }
        } catch {
        }
    }

    private func applyThreadMetadata(_ thread: ChatThreadInfo) {
        activeThreadId = thread.id
        activeThreadTitle = thread.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeThreadChannel = thread.channel?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeThreadType = thread.threadType?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeThreadState = thread.state?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mapHistory(_ history: ChatThreadHistoryResponse) -> [ChatMessage] {
        var mapped = mapTurns(history.turns)
        if let gate = mapPendingGate(history.pendingGate) {
            mapped.append(
                ChatMessage(
                    role: .assistant,
                    content: "",
                    timestamp: pendingGateTimestamp(from: history),
                    stateText: "等待确认",
                    pendingGate: gate
                )
            )
        }
        return mapped.sorted { $0.timestamp < $1.timestamp }
    }

    private func mapTurns(_ turns: [ChatThreadTurn]) -> [ChatMessage] {
        var mapped: [ChatMessage] = []
        for turn in turns {
            let turnTimestamp = parseDate(turn.startedAt) ?? parseDate(turn.completedAt) ?? Date()
            let user = turn.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !user.isEmpty {
                mapped.append(ChatMessage(role: .user, content: user, timestamp: turnTimestamp))
            }

            let reply = (turn.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let toolCalls = mapToolCalls(turn.toolCalls)
            let generatedImages = mapGeneratedImages(turn.generatedImages)
            if !reply.isEmpty || !toolCalls.isEmpty || !generatedImages.isEmpty {
                mapped.append(
                    ChatMessage(
                        role: .assistant,
                        content: reply,
                        timestamp: parseDate(turn.completedAt) ?? turnTimestamp,
                        stateText: stateDisplayText(turn.state),
                        toolCalls: toolCalls,
                        generatedImages: generatedImages
                    )
                )
            }
        }
        return mapped
    }

    private func mergeHistory(
        _ history: ChatThreadHistoryResponse,
        pendingUserText: String,
        pendingUserTimestamp: Date,
        assistantFallback: String?
    ) -> [ChatMessage] {
        var merged = mapHistory(history)
        let normalizedPendingUser = normalizeMessageText(pendingUserText)
        let historyContainsUser = merged.contains {
            $0.role == .user && normalizeMessageText($0.content) == normalizedPendingUser
        }

        if !historyContainsUser {
            merged.append(ChatMessage(role: .user, content: pendingUserText, timestamp: pendingUserTimestamp))
        }

        let normalizedAssistantFallback = normalizeMessageText(assistantFallback ?? "")
        if !normalizedAssistantFallback.isEmpty {
            let historyContainsAssistant = merged.contains {
                $0.role == .assistant && normalizeMessageText($0.content) == normalizedAssistantFallback
            }
            if !historyContainsAssistant {
                merged.append(
                    ChatMessage(
                        role: .assistant,
                        content: assistantFallback ?? "",
                        timestamp: latestHistoryTimestamp(from: history) ?? Date(),
                        stateText: stateDisplayText(history.turns.last?.state)
                    )
                )
            }
        }

        return merged.sorted { $0.timestamp < $1.timestamp }
    }

    private func mapToolCalls(_ toolCalls: [ChatToolCallDTO]?) -> [ChatMessage.ToolCall] {
        (toolCalls ?? []).map {
            ChatMessage.ToolCall(
                id: $0.id,
                name: $0.name,
                hasError: $0.hasError,
                hasResult: $0.hasResult,
                resultPreview: $0.resultPreview,
                error: $0.error
            )
        }
    }

    private func mapGeneratedImages(_ images: [ChatGeneratedImageDTO]?) -> [ChatMessage.GeneratedImage] {
        (images ?? []).map {
            ChatMessage.GeneratedImage(
                id: $0.id,
                eventId: $0.eventId,
                imageData: decodeDataURL($0.dataUrl),
                path: $0.path
            )
        }
    }

    private func mapPendingGate(_ gate: ChatPendingGateDTO?) -> ChatMessage.PendingGate? {
        guard let gate else { return nil }
        return ChatMessage.PendingGate(
            requestId: gate.requestId,
            toolName: gate.toolName,
            description: gate.description,
            parametersSummary: gate.parameters.flatMap { stringify(json: .object($0)) },
            resumeSummary: gate.resumeKind.flatMap { stringify(json: $0) },
            allowAlways: gate.allowAlways ?? false
        )
    }

    private func decodeDataURL(_ raw: String?) -> Data? {
        guard let raw, let comma = raw.firstIndex(of: ",") else { return nil }
        let payload = String(raw[raw.index(after: comma)...])
        return Data(base64Encoded: payload)
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let fractional = ISO8601DateFormatter.fractional.date(from: raw) {
            return fractional
        }
        return ISO8601DateFormatter().date(from: raw)
    }

    private func latestHistoryTimestamp(from history: ChatThreadHistoryResponse) -> Date? {
        history.turns.last.flatMap { parseDate($0.completedAt) ?? parseDate($0.startedAt) }
    }

    private func pendingGateTimestamp(from history: ChatThreadHistoryResponse) -> Date {
        latestHistoryTimestamp(from: history) ?? Date()
    }

    private func normalizeMessageText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedLabel(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func stateDisplayText(_ raw: String?) -> String? {
        guard let raw = normalizedLabel(raw) else { return nil }
        let normalized = raw.lowercased()
        if normalized.contains("approval") || normalized.contains("gate") {
            return "等待确认"
        }
        if normalized.contains("run") || normalized.contains("stream") || normalized.contains("progress") || normalized.contains("pending") {
            return "处理中"
        }
        if normalized.contains("fail") || normalized.contains("error") {
            return "失败"
        }
        if normalized.contains("complete") || normalized.contains("done") || normalized.contains("idle") {
            return "已完成"
        }
        return raw
    }

    private func stringify(json: JSONValue) -> String? {
        let raw = unwrap(json)
        if let string = raw as? String {
            return string
        }
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: raw)
        }
        return string
    }

    private func unwrap(_ value: JSONValue) -> Any {
        switch value {
        case .string(let string):
            return string
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .bool(let bool):
            return bool
        case .array(let array):
            return array.map(unwrap)
        case .object(let object):
            return object.mapValues(unwrap)
        case .null:
            return NSNull()
        }
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
