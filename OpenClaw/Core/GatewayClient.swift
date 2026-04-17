import Foundation
internal import Combine
import os

@MainActor
enum AppDebugSettings {
    private static let key = "openclaw.debug.enabled"

    static var debugEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

@MainActor
final class AppLogStore: ObservableObject {
    static let shared = AppLogStore()

    @Published private(set) var entries: [String] = []
    private let limit = 200

    private init() {}

    func append(_ message: String) {
        guard AppDebugSettings.debugEnabled else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        entries.append("[\(timestamp)] \(message)")
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    func clear() {
        entries.removeAll()
    }

    var exportText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
        let header = [
            "App: 开爪 / OpenClaw",
            "App 版本: \(version)",
            "Build: \(build)",
            "",
            "日志:",
        ]
        return (header + entries).joined(separator: "\n")
    }
}

// MARK: - Protocol (Dependency Inversion)

/// Abstraction over gateway networking — ViewModels depend on this, not concrete types.
protocol GatewayClientProtocol: Sendable {
    func stats<Response: Decodable>(_ path: String) async throws -> Response
    func statsPost<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response
    func invoke<Body: Encodable, Response: Decodable>(_ body: Body) async throws -> Response
    func listMemoryFiles() async throws -> [MemoryHTTPEntryDTO]
    func readMemoryFile(path: String) async throws -> MemoryHTTPReadResponseDTO
    func chatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse
    func streamChat(message: String, previousResponseId: String?) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func listChatThreads() async throws -> ChatThreadListResponse
    func createChatThread() async throws -> ChatThreadInfo
    func loadChatHistory(threadId: String) async throws -> ChatThreadHistoryResponse
    func sendThreadMessage(threadId: String, content: String) async throws -> ChatSendResponse
    func waitForThreadTurn(threadId: String, afterTurnCount: Int, timeout: TimeInterval) async throws -> ChatStreamPollResult
    func listRoutines() async throws -> [RoutineJobDTO]
    func loadRoutineRuns(jobId: String) async throws -> RoutineRunsResponseDTO
    func triggerRoutine(jobId: String, mode: String) async throws
    func setRoutineEnabled(jobId: String, enabled: Bool) async throws
    func validateConnection() async throws
    func validateGatewayConnection(testMessage: String) async throws -> GatewayValidationResult
}

struct GatewayValidationResult: Sendable {
    let summary: String
    let details: [String]
}

private struct MappedThreadCompletion {
    let response: ChatCompletionResponse
    let threadId: String
}

// MARK: - Implementation

/// Thread-safe HTTP client. Configured with a base URL and token.
struct GatewayClient: GatewayClientProtocol, Sendable {
    private static let logger = Logger(subsystem: "co.uk.appwebdev.openclaw", category: "Gateway")
    @MainActor private static let appLog = AppLogStore.shared

    @MainActor
    private static func log(_ message: String) {
        appLog.append(message)
    }

    @MainActor
    private static func logError(_ prefix: String, error: Error) {
        appLog.append("\(prefix): \(error.localizedDescription)")
    }

    private static let longRunningSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900
        return URLSession(configuration: config)
    }()

    private let baseURL: URL
    private let token: String

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    /// Convenience init from AccountStore.
    init?(accountStore: AccountStore) {
        guard let url = accountStore.activeBaseURL(),
              let token = accountStore.activeToken() else { return nil }
        self.init(baseURL: url, token: token)
    }

    // MARK: - GET /stats/*

    func stats<Response: Decodable>(_ path: String) async throws -> Response {
        let (data, _) = try await request("GET", path: path)
        return try JSONDecoder.snakeCase.decode(Response.self, from: data)
    }

    // MARK: - POST /stats/*

    func statsPost<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let bodyData = try JSONEncoder().encode(body)
        let (data, _) = try await request("POST", path: path, body: bodyData)
        return try JSONDecoder.snakeCase.decode(Response.self, from: data)
    }

    func invoke<Body: Encodable, Response: Decodable>(_ body: Body) async throws -> Response {
        let requestBody = try JSONEncoder().encode(body)
        return try await invokeRaw(method: "invoke", body: requestBody)
    }

    func listMemoryFiles() async throws -> [MemoryHTTPEntryDTO] {
        let (data, _) = try await request("GET", path: "api/memory/list")
        let response = try JSONDecoder().decode(MemoryHTTPListResponseDTO.self, from: data)
        return response.entries
    }

    func readMemoryFile(path: String) async throws -> MemoryHTTPReadResponseDTO {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let (data, _) = try await request("GET", path: "api/memory/read?path=\(encoded)")
        return try JSONDecoder().decode(MemoryHTTPReadResponseDTO.self, from: data)
    }

    func chatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let mapped = try await performThreadCompletion(
            system: request.instructions ?? "",
            user: request.input.first?.content ?? "",
            requestedThreadId: request.previousResponseId,
            stream: request.stream
        )
        return mapped.response
    }

    func validateGatewayConnection(testMessage: String = "ping") async throws -> GatewayValidationResult {
        await Self.log("开始验证聊天主链路 host=\(baseURL.host() ?? "unknown") tokenLoaded=\(!token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")
        do {
            try await validateConnection()

            var details: [String] = ["模型接口 /v1/models 可达"]
            let thread = try await createChatThread()
            let threadId = thread.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !threadId.isEmpty else {
                throw GatewayError.invalidResponse
            }
            details.append("线程创建成功: \(threadId)")

            let baselineHistory = try await loadChatHistory(threadId: threadId)
            details.append("历史读取成功，当前共有 \(baselineHistory.turns.count) 条 turn")

            _ = try await sendThreadMessage(threadId: threadId, content: testMessage)
            details.append("消息发送成功: /api/chat/send")

            let poll = try await waitForThreadTurn(
                threadId: threadId,
                afterTurnCount: baselineHistory.turns.count,
                timeout: 20
            )
            let reply = (poll.latestTurn.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            details.append(reply.isEmpty ? "历史轮询成功，但最新回复为空" : "历史轮询成功，已收到回复")
            await Self.log("聊天主链路验证成功，thread=\(threadId)")

            return GatewayValidationResult(
                summary: "聊天主链路可用：已完成模型探活、线程创建、发送消息与历史轮询。",
                details: details
            )
        } catch {
            await Self.logError("聊天主链路验证失败", error: error)
            throw error
        }
    }

    // MARK: - Thread-based chat

    func streamChat(message: String, previousResponseId: String?) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let mapped = try await performThreadCompletion(
                        system: "",
                        user: message,
                        requestedThreadId: previousResponseId,
                        stream: true
                    )
                    if let text = mapped.response.text, !text.isEmpty {
                        continuation.yield(.delta(text))
                    }
                    continuation.yield(.completed(mapped.response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func performThreadCompletion(
        system: String,
        user: String,
        requestedThreadId: String?,
        stream: Bool
    ) async throws -> MappedThreadCompletion {
        _ = stream
        let normalizedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUser.isEmpty else {
            throw GatewayError.invalidResponse
        }

        let threadId = try await resolveThreadId(requestedThreadId)
        let baselineHistory = try await loadChatHistory(threadId: threadId)
        let content = composeThreadMessage(system: system, user: normalizedUser)

        Self.logger.debug("POST /api/chat/send (thread_id: \(threadId))")
        await Self.log("发送聊天消息，thread=\(threadId)")
        _ = try await sendThreadMessage(threadId: threadId, content: content)

        let poll = try await waitForThreadTurn(
            threadId: threadId,
            afterTurnCount: baselineHistory.turns.count,
            timeout: 45
        )

        let latest = poll.latestTurn
        if latest.state.lowercased().contains("failed") {
            let errorText = (latest.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            await Self.log("聊天线程失败，thread=\(threadId) state=\(latest.state) detail=\(errorText.isEmpty ? "empty" : errorText)")
            throw GatewayError.serverError(500, type: "thread_failed", message: latest.response ?? "IronClaw 线程响应失败。")
        }

        await Self.log("聊天线程完成，thread=\(threadId)")

        let response = ChatCompletionResponse(
            id: threadId,
            model: nil,
            output: mappedOutput(text: latest.response),
            usage: nil,
            error: nil
        )
        return MappedThreadCompletion(response: response, threadId: threadId)
    }

    private func resolveThreadId(_ requestedThreadId: String?) async throws -> String {
        if let requestedThreadId {
            let trimmed = requestedThreadId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return try await createChatThread().id
    }

    private func composeThreadMessage(system: String, user: String) -> String {
        let normalizedSystem = system.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSystem.isEmpty {
            return user
        }
        return "系统指令:\n\(normalizedSystem)\n\n用户消息:\n\(user)"
    }

    private func mappedOutput(text: String?) -> [ChatCompletionResponse.OutputItem]? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return [
            .message(
                .init(
                    role: .assistant,
                    content: [.outputText(.init(text: text))]
                )
            )
        ]
    }

    func listChatThreads() async throws -> ChatThreadListResponse {
        let (data, _) = try await request("GET", path: "api/chat/threads")
        return try JSONDecoder.snakeCase.decode(ChatThreadListResponse.self, from: data)
    }

    func createChatThread() async throws -> ChatThreadInfo {
        let (data, _) = try await request("POST", path: "api/chat/thread/new")
        return try JSONDecoder.snakeCase.decode(ChatThreadInfo.self, from: data)
    }

    func loadChatHistory(threadId: String) async throws -> ChatThreadHistoryResponse {
        let escaped = threadId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? threadId
        let (data, _) = try await request("GET", path: "api/chat/history?thread_id=\(escaped)")
        return try JSONDecoder.snakeCase.decode(ChatThreadHistoryResponse.self, from: data)
    }

    func sendThreadMessage(threadId: String, content: String) async throws -> ChatSendResponse {
        let body = ChatSendRequest(threadId: threadId, content: content)
        let bodyData = try JSONEncoder().encode(body)
        let (data, _) = try await request("POST", path: "api/chat/send", body: bodyData)
        return try JSONDecoder.snakeCase.decode(ChatSendResponse.self, from: data)
    }

    func waitForThreadTurn(threadId: String, afterTurnCount: Int, timeout: TimeInterval) async throws -> ChatStreamPollResult {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let history = try await loadChatHistory(threadId: threadId)
            if history.turns.count > afterTurnCount, let latestTurn = history.turns.last {
                return ChatStreamPollResult(history: history, latestTurn: latestTurn)
            }
            try await Task.sleep(nanoseconds: 800_000_000)
        }
        throw GatewayError.serverError(408, type: "timeout", message: "等待线程响应超时")
    }

    func listRoutines() async throws -> [RoutineJobDTO] {
        let (data, _) = try await request("GET", path: "api/routines")
        let response = try JSONDecoder.snakeCase.decode(RoutineListResponseDTO.self, from: data)
        return response.routines
    }

    func loadRoutineRuns(jobId: String) async throws -> RoutineRunsResponseDTO {
        let escaped = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        let (data, _) = try await request("GET", path: "api/routines/\(escaped)/runs")
        return try JSONDecoder.snakeCase.decode(RoutineRunsResponseDTO.self, from: data)
    }

    func triggerRoutine(jobId: String, mode: String = "force") async throws {
        let escaped = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        let bodyData = try JSONSerialization.data(withJSONObject: ["mode": mode])
        _ = try await request("POST", path: "api/routines/\(escaped)/trigger", body: bodyData)
    }

    func setRoutineEnabled(jobId: String, enabled: Bool) async throws {
        let escaped = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        let bodyData = try JSONSerialization.data(withJSONObject: ["enabled": enabled])
        _ = try await request("POST", path: "api/routines/\(escaped)/toggle", body: bodyData)
    }

    func validateConnection() async throws {
        _ = try await stats("v1/models") as OpenAIModelsResponse
    }

    private func request(_ method: String, path: String, body: Data? = nil) async throws -> (Data, URLResponse) {
        let token = try requireToken()
        let url = try buildURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        Self.logger.debug("\(method) /\(path)")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTPResponse(response, data: data, path: path)
        return (data, response)
    }

    private func invokeRaw<Response: Decodable>(method: String, body: Data) async throws -> Response {
        let token = try requireToken()
        let url = try buildURL("tools/invoke")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        await Self.log("开始调用扩展接口 endpoint=/tools/invoke action=\(method) host=\(url.host() ?? "unknown") tokenLoaded=\(!token.isEmpty)")
        Self.logger.debug("POST /tools/invoke [\(method)]")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTPResponse(response, data: data, path: "tools/invoke")
        await Self.log("扩展接口调用成功 endpoint=/tools/invoke action=\(method)")
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func requireToken() throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GatewayError.noToken }
        return trimmed
    }

    private func buildURL(_ path: String) throws -> URL {
        let trimmedBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedBase)/\(trimmedPath)") else { throw GatewayError.invalidResponse }
        return url
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data, path: String) throws {
        guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        let body = String(data: data, encoding: .utf8) ?? ""

        if (200...299).contains(http.statusCode) {
            if isLikelyControlPage(body, response: http) {
                throw GatewayError.controlPageReturned(path: path)
            }
            return
        }

        if http.statusCode == 404 {
            Task { @MainActor in
                AppLogStore.shared.append("接口未启用 endpoint=/\(path) status=404 note=该失败通常表示扩展接口不可用，聊天主链路可能仍然正常")
            }
        }

        if let envelope = try? JSONDecoder().decode(GatewayErrorEnvelope.self, from: data), let err = envelope.error {
            Task { @MainActor in
                AppLogStore.shared.append("接口调用失败 endpoint=/\(path) status=\(http.statusCode) type=\(err.type) message=\(err.message)")
            }
            throw GatewayError.serverError(http.statusCode, type: err.type, message: err.message)
        }
        Task { @MainActor in
            let preview = body.isEmpty ? "(empty)" : String(body.prefix(500))
            AppLogStore.shared.append("接口调用失败 endpoint=/\(path) status=\(http.statusCode) body=\(preview)")
        }
        throw GatewayError.httpError(http.statusCode, body: body)
    }

    private func isLikelyControlPage(_ body: String, response: HTTPURLResponse) -> Bool {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let sample = body.prefix(512).lowercased()
        guard contentType.contains("text/html") || sample.contains("<!doctype html") || sample.contains("<html") else {
            return false
        }

        return sample.contains("openclaw") ||
               sample.contains("hermes") ||
               sample.contains("control ui") ||
               sample.contains("<head") ||
               sample.contains("<body")
    }
}

private extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

struct RoutineListResponseDTO: Decodable, Sendable {
    let routines: [RoutineJobDTO]
}

struct RoutineJobDTO: Decodable, Sendable {
    let id: String
    let name: String
    let description: String?
    let enabled: Bool?
    let triggerType: String?
    let triggerRaw: String?
    let triggerSummary: String?
    let actionType: String?
    let lastRunAt: String?
    let nextFireAt: String?
    let consecutiveFailures: Int?
}

private extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

struct OpenAIModelsResponse: Decodable, Sendable {
    let data: [OpenAIModel]

    struct OpenAIModel: Decodable, Sendable {
        let id: String
    }
}

enum GatewayError: LocalizedError {
    case noToken
    case invalidResponse
    case controlPageReturned(path: String)
    case serverError(Int, type: String, message: String)
    case httpError(Int, body: String)

    var errorDescription: String? {
        switch self {
        case .noToken:
            "缺少访问令牌。"
        case .invalidResponse:
            "服务端返回了无法识别的响应。"
        case .controlPageReturned(let path):
            "请求 /\(path) 时返回了控制台页面，而不是 API JSON。"
        case .serverError(_, _, let message):
            message
        case .httpError(let status, let body):
            body.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(body)"
        }
    }
}

private struct GatewayErrorEnvelope: Decodable {
    struct ErrorBody: Decodable {
        let type: String
        let message: String
    }

    let error: ErrorBody?
}

struct ChatCompletionRequest: Sendable {
    let instructions: String?
    let input: [InputItem]
    let previousResponseId: String?
    let stream: Bool

    init(system: String, user: String, previousResponseId: String? = nil, stream: Bool = false) {
        self.instructions = system.isEmpty ? nil : system
        self.input = [InputItem(content: user)]
        self.previousResponseId = previousResponseId
        self.stream = stream
    }

    struct InputItem: Sendable {
        let content: String
    }
}

struct ChatCompletionResponse: Sendable {
    let id: String
    let model: String?
    let output: [OutputItem]?
    let usage: Usage?
    let error: String?

    var text: String? {
        output?.compactMap {
            if case .message(let message) = $0 {
                return message.content.compactMap {
                    if case .outputText(let item) = $0 {
                        return item.text
                    }
                    return nil
                }.joined(separator: "")
            }
            return nil
        }.joined(separator: "\n")
    }

    enum OutputItem: Sendable {
        case message(Message)
    }

    struct Message: Sendable {
        let role: Role
        let content: [ContentItem]
    }

    enum ContentItem: Sendable {
        case outputText(OutputText)
    }

    struct OutputText: Sendable {
        let text: String
    }

    struct Usage: Sendable {}

    enum Role: Sendable {
        case assistant
    }
}

extension ChatCompletionResponse.OutputItem {
    static func message(_ message: ChatCompletionResponse.Message) -> Self { .message(message) }
}

extension ChatCompletionResponse.ContentItem {
    static func outputText(_ item: ChatCompletionResponse.OutputText) -> Self { .outputText(item) }
}

struct ChatThreadListResponse: Decodable, Sendable {
    let threads: [ChatThreadInfo]
}

struct ChatThreadInfo: Decodable, Sendable {
    let id: String
}

struct ChatThreadHistoryResponse: Decodable, Sendable {
    let turns: [ChatThreadTurn]
}

struct ChatThreadTurn: Decodable, Sendable {
    let state: String
    let response: String?
}

struct ChatSendRequest: Encodable, Sendable {
    let threadId: String
    let content: String
}

struct ChatSendResponse: Decodable, Sendable {}

struct ChatStreamPollResult: Sendable {
    let history: ChatThreadHistoryResponse
    let latestTurn: ChatThreadTurn
}

enum ChatStreamEvent: Sendable {
    case delta(String)
    case completed(ChatCompletionResponse)
}

struct RoutineRunsResponseDTO: Decodable, Sendable {}

    func clear() {
        entries.removeAll()
    }

    var exportText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
        let header = [
            "App: 开爪 / OpenClaw",
            "App 版本: \(version)",
            "Build: \(build)",
            "",
            "日志:",
        ]
        return (header + entries).joined(separator: "\n")
    }
}

// MARK: - Protocol (Dependency Inversion)

/// Abstraction over gateway networking — ViewModels depend on this, not concrete types.
protocol GatewayClientProtocol: Sendable {
    func stats<Response: Decodable>(_ path: String) async throws -> Response
    func statsPost<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response
    func invoke<Body: Encodable, Response: Decodable>(_ body: Body) async throws -> Response
    func listMemoryFiles() async throws -> [MemoryHTTPEntryDTO]
    func readMemoryFile(path: String) async throws -> MemoryHTTPReadResponseDTO
    func chatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse
    func streamChat(message: String, previousResponseId: String?) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func listChatThreads() async throws -> ChatThreadListResponse
    func createChatThread() async throws -> ChatThreadInfo
    func loadChatHistory(threadId: String) async throws -> ChatThreadHistoryResponse
    func sendThreadMessage(threadId: String, content: String) async throws -> ChatSendResponse
    func waitForThreadTurn(threadId: String, afterTurnCount: Int, timeout: TimeInterval) async throws -> ChatStreamPollResult
    func listRoutines() async throws -> [RoutineJobDTO]
    func loadRoutineRuns(jobId: String) async throws -> RoutineRunsResponseDTO
    func triggerRoutine(jobId: String, mode: String) async throws
    func setRoutineEnabled(jobId: String, enabled: Bool) async throws
    func validateConnection() async throws
    func validateGatewayConnection(testMessage: String) async throws -> GatewayValidationResult
}

struct GatewayValidationResult: Sendable {
    let summary: String
    let details: [String]
}

private struct MappedThreadCompletion {
    let response: ChatCompletionResponse
    let threadId: String
}

// MARK: - Implementation

/// Thread-safe HTTP client. Configured with a base URL and token.
struct GatewayClient: GatewayClientProtocol, Sendable {
    private static let logger = Logger(subsystem: "co.uk.appwebdev.openclaw", category: "Gateway")
    @MainActor private static let appLog = AppLogStore.shared

    @MainActor
    private static func log(_ message: String) {
        appLog.append(message)
    }

    @MainActor
    private static func logError(_ prefix: String, error: Error) {
        appLog.append("\(prefix): \(error.localizedDescription)")
    }

    private static let longRunningSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900
        return URLSession(configuration: config)
    }()

    private let baseURL: URL
    private let token: String

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    /// Convenience init from AccountStore.
    init?(accountStore: AccountStore) {
        guard let url = accountStore.activeBaseURL(),
              let token = accountStore.activeToken() else { return nil }
        self.init(baseURL: url, token: token)
    }

    // MARK: - GET /stats/*

    func stats<Response: Decodable>(_ path: String) async throws -> Response {
        let (data, _) = try await request("GET", path: path)
        return try JSONDecoder.snakeCase.decode(Response.self, from: data)
    }

    // MARK: - POST /stats/*

    func statsPost<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let bodyData = try JSONEncoder().encode(body)
        let (data, _) = try await request("POST", path: path, body: bodyData)
        return try JSONDecoder.snakeCase.decode(Response.self, from: data)
    }

    func invoke<Body: Encodable, Response: Decodable>(_ body: Body) async throws -> Response {
        let requestBody = try JSONEncoder().encode(body)
        return try await invokeRaw(method: "invoke", body: requestBody)
    }

    func listMemoryFiles() async throws -> [MemoryHTTPEntryDTO] {
        let (data, _) = try await request("GET", path: "api/memory/list")
        let response = try JSONDecoder().decode(MemoryHTTPListResponseDTO.self, from: data)
        return response.entries
    }

    func readMemoryFile(path: String) async throws -> MemoryHTTPReadResponseDTO {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let (data, _) = try await request("GET", path: "api/memory/read?path=\(encoded)")
        return try JSONDecoder().decode(MemoryHTTPReadResponseDTO.self, from: data)
    }

    func chatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let mapped = try await performThreadCompletion(
            system: request.instructions ?? "",
            user: request.input.first?.content ?? "",
            requestedThreadId: request.previousResponseId,
            stream: request.stream
        )
        return mapped.response
    }

    func validateGatewayConnection(testMessage: String = "ping") async throws -> GatewayValidationResult {
        await Self.log("开始验证聊天主链路 host=\(baseURL.host() ?? "unknown") tokenLoaded=\(!token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")
        do {
            try await validateConnection()

            var details: [String] = ["模型接口 /v1/models 可达"]
            let thread = try await createChatThread()
            let threadId = thread.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !threadId.isEmpty else {
                throw GatewayError.invalidResponse
            }
            details.append("线程创建成功: \(threadId)")

            let baselineHistory = try await loadChatHistory(threadId: threadId)
            details.append("历史读取成功，当前共有 \(baselineHistory.turns.count) 条 turn")

            _ = try await sendThreadMessage(threadId: threadId, content: testMessage)
            details.append("消息发送成功: /api/chat/send")

            let poll = try await waitForThreadTurn(
                threadId: threadId,
                afterTurnCount: baselineHistory.turns.count,
                timeout: 20
            )
            let reply = (poll.latestTurn.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            details.append(reply.isEmpty ? "历史轮询成功，但最新回复为空" : "历史轮询成功，已收到回复")
            await Self.log("聊天主链路验证成功，thread=\(threadId)")

            return GatewayValidationResult(
                summary: "聊天主链路可用：已完成模型探活、线程创建、发送消息与历史轮询。",
                details: details
            )
        } catch {
            await Self.logError("聊天主链路验证失败", error: error)
            throw error
        }
    }

    // MARK: - Thread-based chat

    func streamChat(message: String, previousResponseId: String?) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let mapped = try await performThreadCompletion(
                        system: "",
                        user: message,
                        requestedThreadId: previousResponseId,
                        stream: true
                    )
                    if let text = mapped.response.text, !text.isEmpty {
                        continuation.yield(.delta(text))
                    }
                    continuation.yield(.completed(mapped.response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func performThreadCompletion(
        system: String,
        user: String,
        requestedThreadId: String?,
        stream: Bool
    ) async throws -> MappedThreadCompletion {
        _ = stream
        let normalizedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUser.isEmpty else {
            throw GatewayError.invalidResponse
        }

        let threadId = try await resolveThreadId(requestedThreadId)
        let baselineHistory = try await loadChatHistory(threadId: threadId)
        let content = composeThreadMessage(system: system, user: normalizedUser)

        Self.logger.debug("POST /api/chat/send (thread_id: \(threadId))")
        await Self.log("发送聊天消息，thread=\(threadId)")
        _ = try await sendThreadMessage(threadId: threadId, content: content)

        let poll = try await waitForThreadTurn(
            threadId: threadId,
            afterTurnCount: baselineHistory.turns.count,
            timeout: 45
        )

        let latest = poll.latestTurn
        if latest.state.lowercased().contains("failed") {
            let errorText = (latest.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            await Self.log("聊天线程失败，thread=\(threadId) state=\(latest.state) detail=\(errorText.isEmpty ? "empty" : errorText)")
            throw GatewayError.serverError(500, type: "thread_failed", message: latest.response ?? "IronClaw 线程响应失败。")
        }

        await Self.log("聊天线程完成，thread=\(threadId)")

        let response = ChatCompletionResponse(
            id: threadId,
            model: nil,
            output: mappedOutput(text: latest.response),
            usage: nil,
            error: nil
        )
        return MappedThreadCompletion(response: response, threadId: threadId)
    }

    private func resolveThreadId(_ requestedThreadId: String?) async throws -> String {
        if let requestedThreadId {
            let trimmed = requestedThreadId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return try await createChatThread().id
    }

    private func composeThreadMessage(system: String, user: String) -> String {
        let normalizedSystem = system.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSystem.isEmpty {
            return user
        }
        return "系统指令:\n\(normalizedSystem)\n\n用户消息:\n\(user)"
    }

    private func mappedOutput(text: String?) -> [ChatCompletionResponse.OutputItem]? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return [
            ChatCompletionResponse.OutputItem(
                type: "message",
                role: "assistant",
                content: [
                    ChatCompletionResponse.ContentItem(type: "output_text", text: text)
                ]
            )
        ]
    }

    // MARK: - Thread APIs

    func listChatThreads() async throws -> ChatThreadListResponse {
        let (data, _) = try await request("GET", path: "api/chat/threads")
        return try JSONDecoder.snakeCase.decode(ChatThreadListResponse.self, from: data)
    }

    func createChatThread() async throws -> ChatThreadInfo {
        await Self.log("开始创建聊天线程：/api/chat/thread/new")
        let (data, _) = try await request("POST", path: "api/chat/thread/new")
        let thread = try JSONDecoder.snakeCase.decode(ChatThreadInfo.self, from: data)
        await Self.log("聊天线程创建成功，thread=\(thread.id)")
        return thread
    }

    func loadChatHistory(threadId: String) async throws -> ChatThreadHistoryResponse {
        let escaped = threadId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? threadId
        await Self.log("开始读取聊天历史，thread=\(threadId) endpoint=/api/chat/history host=\(baseURL.host() ?? "unknown")")
        let (data, _) = try await request("GET", path: "api/chat/history?thread_id=\(escaped)")
        do {
            let history = try JSONDecoder.snakeCase.decode(ChatThreadHistoryResponse.self, from: data)
            await Self.log("聊天历史读取成功，thread=\(threadId) turns=\(history.turns.count)")
            return history
        } catch {
            let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8 body size=\(data.count)>"
            await Self.log("聊天历史解码失败，thread=\(threadId) bodyPreview=\(preview)")
            throw GatewayError.httpError(200, body: "聊天历史响应结构不兼容：\(error.localizedDescription)")
        }
    }

    func sendThreadMessage(threadId: String, content: String) async throws -> ChatSendResponse {
        await Self.log("开始发送聊天消息，thread=\(threadId) endpoint=/api/chat/send host=\(baseURL.host() ?? "unknown") tokenLoaded=\(!token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) chars=\(content.count)")
        let body = try JSONEncoder().encode(
            ChatSendRequest(
                content: content,
                threadId: threadId,
                timezone: TimeZone.current.identifier
            )
        )
        let (data, _) = try await request("POST", path: "api/chat/send", body: body)
        let response = try JSONDecoder.snakeCase.decode(ChatSendResponse.self, from: data)
        await Self.log("聊天消息发送成功，thread=\(threadId)")
        return response
    }

    func waitForThreadTurn(threadId: String, afterTurnCount: Int, timeout: TimeInterval = 30) async throws -> ChatStreamPollResult {
        let deadline = Date().addingTimeInterval(timeout)
        var attempt = 0
        while Date() < deadline {
            attempt += 1
            let history = try await loadChatHistory(threadId: threadId)
            let latestState = history.turns.last?.state ?? "none"
            await Self.log("轮询聊天历史，thread=\(threadId) attempt=\(attempt) turns=\(history.turns.count) latest=\(latestState)")
            if let latest = history.turns.last,
               history.turns.count > afterTurnCount,
               latest.isTerminal {
                await Self.log("聊天历史轮询命中终态，thread=\(threadId) state=\(latest.state)")
                return ChatStreamPollResult(history: history, latestTurn: latest)
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        await Self.log("聊天历史轮询超时，thread=\(threadId) timeout=\(Int(timeout))s")
        throw GatewayError.httpError(408, body: "Timed out waiting for IronClaw thread response")
    }

    func listRoutines() async throws -> [RoutineJobDTO] {
        await Self.log("开始读取定时任务列表：/api/routines")
        let (data, _) = try await request("GET", path: "api/routines")
        let response = try JSONDecoder.snakeCase.decode(RoutineListResponseDTO.self, from: data)
        await Self.log("定时任务列表读取成功，count=\(response.routines.count)")
        return response.routines
    }

    func loadRoutineRuns(jobId: String) async throws -> RoutineRunsResponseDTO {
        let escaped = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        await Self.log("开始读取任务运行历史，job=\(jobId)")
        let (data, _) = try await request("GET", path: "api/routines/\(escaped)/runs")
        let response = try JSONDecoder.snakeCase.decode(RoutineRunsResponseDTO.self, from: data)
        await Self.log("任务运行历史读取成功，job=\(jobId) count=\(response.runs.count)")
        return response
    }

    func triggerRoutine(jobId: String, mode: String = "force") async throws {
        let escaped = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        await Self.log("开始触发任务，job=\(jobId) mode=\(mode)")
        let body = try JSONEncoder().encode(RoutineTriggerRequest(mode: mode))
        _ = try await request("POST", path: "api/routines/\(escaped)/trigger", body: body)
        await Self.log("任务触发成功，job=\(jobId)")
    }

    func setRoutineEnabled(jobId: String, enabled: Bool) async throws {
        let escaped = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        await Self.log("开始切换任务启用状态，job=\(jobId) enabled=\(enabled)")
        let body = try JSONEncoder().encode(RoutineToggleRequest(enabled: enabled))
        _ = try await request("POST", path: "api/routines/\(escaped)/toggle", body: body)
        await Self.log("任务启用状态切换成功，job=\(jobId) enabled=\(enabled)")
    }

    func validateConnection() async throws {
        let token = try requireToken()
        let url = try buildURL("v1/models")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        await Self.log("开始验证模型接口：/v1/models host=\(url.host() ?? "unknown") tokenLoaded=\(!token.isEmpty)")
        Self.logger.debug("GET /v1/models")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTPResponse(response, data: data, path: "v1/models")
        await Self.log("模型接口验证成功：/v1/models")
    }

    // MARK: - Private helpers

    private func request(_ method: String, path: String, body: Data? = nil) async throws -> (Data, URLResponse) {
        let token = try requireToken()
        let url = try buildURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        Self.logger.debug("\(method) /\(path)")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTPResponse(response, data: data, path: path)
        return (data, response)
    }

    private func invokeRaw<Response: Decodable>(method: String, body: Data) async throws -> Response {
        let token = try requireToken()
        let url = try buildURL("tools/invoke")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        await Self.log("开始调用扩展接口 endpoint=/tools/invoke action=\(method) host=\(url.host() ?? "unknown") tokenLoaded=\(!token.isEmpty)")
        Self.logger.debug("POST /tools/invoke [\(method)]")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTPResponse(response, data: data, path: "tools/invoke")
        await Self.log("扩展接口调用成功 endpoint=/tools/invoke action=\(method)")
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func requireToken() throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GatewayError.noToken }
        return trimmed
    }

    private func buildURL(_ path: String) throws -> URL {
        let trimmedBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedBase)/\(trimmedPath)") else { throw GatewayError.invalidResponse }
        return url
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data, path: String) throws {
        guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        let body = String(data: data, encoding: .utf8) ?? ""

        if (200...299).contains(http.statusCode) {
            if isLikelyControlPage(body, response: http) {
                throw GatewayError.controlPageReturned(path: path)
            }
            return
        }

        if http.statusCode == 404 {
            Task { @MainActor in
                AppLogStore.shared.append("接口未启用 endpoint=/\(path) status=404 note=该失败通常表示扩展接口不可用，聊天主链路可能仍然正常")
            }
        }

        if let envelope = try? JSONDecoder().decode(GatewayErrorEnvelope.self, from: data), let err = envelope.error {
            Task { @MainActor in
                AppLogStore.shared.append("接口调用失败 endpoint=/\(path) status=\(http.statusCode) type=\(err.type) message=\(err.message)")
            }
            throw GatewayError.serverError(http.statusCode, type: err.type, message: err.message)
        }
        Task { @MainActor in
            let preview = body.isEmpty ? "(empty)" : String(body.prefix(500))
            AppLogStore.shared.append("接口调用失败 endpoint=/\(path) status=\(http.statusCode) body=\(preview)")
        }
        throw GatewayError.httpError(http.statusCode, body: body)
    }

    private func isLikelyControlPage(_ body: String, response: HTTPURLResponse) -> Bool {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let sample = body.prefix(512).lowercased()
        guard contentType.contains("text/html") || sample.contains("<!doctype html") || sample.contains("<html") else {
            return false
        }

        return sample.contains("openclaw") ||
               sample.contains("hermes") ||
               sample.contains("control ui") ||
               sample.contains("<head") ||
               sample.contains("<body")
    }
}

private extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

struct RoutineListResponseDTO: Decodable, Sendable {
    let routines: [RoutineJobDTO]
}

struct RoutineJobDTO: Decodable, Sendable {
    let id: String
    let name: String
    let description: String?
    let enabled: Bool?
    let triggerType: String?
    let triggerRaw: String?
    let triggerSummary: String?
    let actionType: String?
    let lastRunAt: String?
    let nextFireAt: String?
    let consecutiveFailures: Int?
    let status: String?
    let verificationStatus: String?
}

struct RoutineRunsResponseDTO: Decodable, Sendable {
    let routineId: String
    let runs: [RoutineRunDTO]
}

struct RoutineRunDTO: Decodable, Sendable {
    let id: String
    let triggerType: String?
    let startedAt: String?
    let completedAt: String?
    let status: String?
    let resultSummary: String?
    let tokensUsed: Int?
    let jobId: String?
}

private struct RoutineTriggerRequest: Encodable {
    let mode: String
}

private struct RoutineToggleRequest: Encodable {
    let enabled: Bool
}
