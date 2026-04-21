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
        do {
            let body = SessionListToolRequest(args: .init(limit: limit))
            let response: SessionListResponseDTO = try await client.invoke(body)
            logger.debug("fetchSessions OK — \(response.sessions.count) sessions")
            AppLogStore.shared.append("会话列表通过 sessions_list 扩展接口加载成功 count=\(response.sessions.count)")
            return response.sessions
                .map(SessionEntry.init)
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        } catch let error as GatewayError {
            guard isUnavailableExtensionError(error) else {
                AppLogStore.shared.append("会话列表加载失败：\(error.localizedDescription)")
                throw error
            }

            AppLogStore.shared.append("sessions_list 不可用，回退到 /api/chat/threads")
            let response = try await client.listChatThreads()
            let sessions = fallbackSessions(from: response, limit: limit)
            AppLogStore.shared.append("线程列表回退成功 count=\(sessions.count)")
            return sessions
        } catch {
            AppLogStore.shared.append("会话列表加载失败：\(error.localizedDescription)")
            throw error
        }
    }

    func fetchTrace(sessionKey: String, limit: Int) async throws -> SessionTrace {
        do {
            let body = SessionHistoryToolRequest(args: .init(sessionKey: sessionKey, limit: limit, includeTools: true))
            let dto: SessionHistoryDTO = try await client.invoke(body)
            await MainActor.run {
                AppLogStore.shared.append("会话轨迹通过 sessions_history 加载成功 session=\(sessionKey)")
            }
            return TraceStep.from(dto: dto)
        } catch let error as GatewayError {
            guard isUnavailableExtensionError(error) else {
                await MainActor.run {
                    AppLogStore.shared.append("会话轨迹加载失败：\(error.localizedDescription)")
                }
                throw error
            }

            await MainActor.run {
                AppLogStore.shared.append("sessions_history 不可用，回退到 /api/chat/history thread=\(sessionKey)")
            }
            let history = try await client.loadChatHistory(threadId: sessionKey)
            let trace = fallbackTrace(sessionKey: sessionKey, history: history, limit: limit)
            await MainActor.run {
                AppLogStore.shared.append("线程历史回退成功 session=\(sessionKey) steps=\(trace.steps.count)")
            }
            return trace
        } catch {
            await MainActor.run {
                AppLogStore.shared.append("会话轨迹加载失败：\(error.localizedDescription)")
            }
            throw error
        }
    }

    private func isUnavailableExtensionError(_ error: GatewayError) -> Bool {
        switch error {
        case .httpError(404, _):
            return true
        case .serverError(404, _, _):
            return true
        default:
            return false
        }
    }

    @MainActor
    private func fallbackSessions(from response: ChatThreadListResponse, limit: Int) -> [SessionEntry] {
        var sessions: [SessionEntry] = []

        if let assistant = response.assistantThread {
            sessions.append(makeSessionEntry(thread: assistant, kind: .main, fallbackTitle: "主会话"))
        }

        for thread in response.threads {
            let type = thread.threadType?.lowercased()
            if type == "assistant" || type == "routine" {
                continue
            }
            sessions.append(makeSessionEntry(thread: thread, kind: .subagent, fallbackTitle: fallbackTitle(for: thread)))
        }

        return Array(
            sessions
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                .prefix(limit)
        )
    }

    @MainActor
    private func makeSessionEntry(thread: ChatThreadInfo, kind: SessionEntry.Kind, fallbackTitle: String) -> SessionEntry {
        SessionEntry(
            id: thread.id,
            kind: kind,
            displayName: thread.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackTitle,
            model: nil,
            status: sessionStatus(from: thread.state),
            updatedAt: parseDate(thread.updatedAt),
            startedAt: parseDate(thread.createdAt),
            totalTokens: 0,
            contextTokens: 0,
            costUsd: 0,
            childSessionCount: 0,
            channel: thread.channel,
            threadType: thread.threadType
        )
    }

    private func fallbackTitle(for thread: ChatThreadInfo) -> String {
        let type = thread.threadType?.lowercased()
        if type == "assistant" {
            return "主会话"
        }
        if type == "routine" {
            return thread.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "定时任务线程"
        }
        return thread.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "聊天线程 \(thread.id.prefix(8))"
    }

    private func sessionStatus(from state: String?) -> SessionEntry.SessionStatus {
        let normalized = state?.lowercased() ?? ""
        if normalized.contains("run") || normalized.contains("stream") || normalized.contains("progress") {
            return .running
        }
        if normalized.contains("idle") || normalized.contains("complete") || normalized.contains("done") {
            return .done
        }
        return .unknown
    }

    private func fallbackTrace(sessionKey: String, history: ChatThreadHistoryResponse, limit: Int) -> SessionTrace {
        let turns = Array(history.turns.suffix(limit))
        var steps: [TraceStep] = []
        var seq = 0

        func appendStep(kind: TraceStep.Kind, timestamp: Date?, stopReason: String? = nil) {
            seq += 1
            steps.append(
                TraceStep(
                    id: "\(sessionKey)-\(seq)",
                    kind: kind,
                    timestamp: timestamp,
                    model: nil,
                    provider: nil,
                    stopReason: stopReason,
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil
                )
            )
        }

        for turn in turns {
            let ts = parseDate(turn.startedAt) ?? parseDate(turn.completedAt)
            let userText = turn.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userText.isEmpty {
                appendStep(kind: .userPrompt(text: userText), timestamp: ts)
            }

            for call in turn.toolCalls ?? [] {
                appendStep(
                    kind: .toolCall(callId: call.id, toolName: call.name, argsSummary: call.resultPreview ?? "等待工具返回结果"),
                    timestamp: ts,
                    stopReason: turn.state
                )
                if call.hasResult || call.hasError || call.resultPreview != nil || call.error != nil {
                    appendStep(
                        kind: .toolResult(
                            callId: call.id,
                            toolName: call.name,
                            output: call.error ?? call.resultPreview ?? "工具调用已完成",
                            isError: call.hasError
                        ),
                        timestamp: ts,
                        stopReason: turn.state
                    )
                }
            }

            if let images = turn.generatedImages, !images.isEmpty {
                appendStep(
                    kind: .text(text: "生成了 \(images.count) 张图片"),
                    timestamp: ts,
                    stopReason: turn.state
                )
            }

            let replyText = (turn.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !replyText.isEmpty {
                appendStep(kind: .text(text: replyText), timestamp: ts, stopReason: turn.state)
            }
        }

        if let gate = history.pendingGate {
            appendStep(
                kind: .toolCall(
                    callId: gate.requestId ?? "pending-gate",
                    toolName: gate.toolName ?? "approval",
                    argsSummary: gate.description ?? "等待用户确认"
                ),
                timestamp: turns.last.flatMap { parseDate($0.completedAt) ?? parseDate($0.startedAt) },
                stopReason: "approval_needed"
            )
        }

        return SessionTrace(
            sessionKey: sessionKey,
            steps: steps,
            truncated: history.turns.count > limit
        )
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = ISO8601DateFormatter.fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
