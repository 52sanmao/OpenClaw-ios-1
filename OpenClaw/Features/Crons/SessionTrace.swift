import Foundation

/// A parsed session history ready for display.
struct SessionTrace: Sendable {
    let sessionKey: String
    let steps: [TraceStep]
    let truncated: Bool
}

/// A single step in the agent execution trace.
struct TraceStep: Sendable, Identifiable {
    let id: String
    let kind: Kind
    let timestamp: Date?
    let model: String?
    let provider: String?
    let stopReason: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    enum Kind: Sendable {
        case systemPrompt(text: String)
        case userPrompt(text: String)
        case thinking(text: String)
        case text(text: String)
        case toolCall(callId: String, toolName: String, argsSummary: String)
        case toolResult(callId: String, toolName: String, output: String, isError: Bool)
    }

    var iconName: String {
        switch kind {
        case .systemPrompt: "gear.badge"
        case .userPrompt:   "person.fill"
        case .thinking:     "brain.head.profile"
        case .text:         "text.bubble"
        case .toolCall:     "terminal"
        case .toolResult:   "doc.text"
        }
    }

    var title: String {
        switch kind {
        case .systemPrompt:                "System Prompt"
        case .userPrompt:                  "Input Prompt"
        case .thinking:                    "Thinking"
        case .text:                        "Response"
        case .toolCall(_, let name, _):    name
        case .toolResult(_, let name, _, _): "\(name) result"
        }
    }

    /// Short content preview for comment context.
    var contentPreview: String {
        switch kind {
        case .systemPrompt(let text), .userPrompt(let text), .thinking(let text), .text(let text):
            String(text.prefix(200))
        case .toolCall(_, let name, let args):
            "\(name): \(String(args.prefix(150)))"
        case .toolResult(_, let name, let output, let isError):
            "\(name) \(isError ? "error" : "result"): \(String(output.prefix(150)))"
        }
    }

    var timestampFormatted: String? {
        guard let timestamp else { return nil }
        return Formatters.absoluteString(for: timestamp)
    }

    /// Parse a full session history DTO into an ordered list of trace steps.
    static func from(dto: SessionHistoryDTO) -> SessionTrace {
        var steps: [TraceStep] = []
        var seq = 0

        for message in dto.messages {
            let ts = message.timestamp.map { Date(timeIntervalSince1970: Double($0) / 1000) }
            let meta = (
                model: message.model,
                provider: message.provider,
                stopReason: message.stopReason,
                inputTokens: message.usage?.inputTokens,
                outputTokens: message.usage?.outputTokens,
                totalTokens: message.usage?.totalTokens
            )

            func makeStep(kind: Kind) -> TraceStep {
                seq += 1
                return TraceStep(
                    id: "\(dto.sessionKey)-\(seq)", kind: kind, timestamp: ts,
                    model: meta.model, provider: meta.provider, stopReason: meta.stopReason,
                    inputTokens: meta.inputTokens, outputTokens: meta.outputTokens, totalTokens: meta.totalTokens
                )
            }

            switch message.role {
            case "system":
                let text = (message.content ?? []).compactMap(\.text).joined(separator: "\n")
                if !text.isEmpty { steps.append(makeStep(kind: .systemPrompt(text: text))) }

            case "user":
                let text = (message.content ?? []).compactMap(\.text).joined(separator: "\n")
                if !text.isEmpty { steps.append(makeStep(kind: .userPrompt(text: text))) }

            case "assistant":
                for item in message.content ?? [] {
                    switch item.type {
                    case "thinking":
                        if let text = item.thinking, !text.isEmpty {
                            steps.append(makeStep(kind: .thinking(text: text)))
                        }
                    case "toolCall":
                        steps.append(makeStep(kind: .toolCall(
                            callId: item.id ?? "",
                            toolName: item.name ?? "unknown",
                            argsSummary: item.arguments?.summary ?? ""
                        )))
                    case "text":
                        if let text = item.text, !text.isEmpty {
                            steps.append(makeStep(kind: .text(text: text)))
                        }
                    default:
                        break
                    }
                }

            case "toolResult":
                let output = (message.content ?? []).compactMap(\.text).joined(separator: "\n")
                steps.append(makeStep(kind: .toolResult(
                    callId: message.toolCallId ?? "",
                    toolName: message.toolName ?? "unknown",
                    output: output,
                    isError: message.isError ?? false
                )))

            default:
                break
            }
        }

        return SessionTrace(
            sessionKey: dto.sessionKey,
            steps: steps,
            truncated: dto.truncated ?? false
        )
    }
}
