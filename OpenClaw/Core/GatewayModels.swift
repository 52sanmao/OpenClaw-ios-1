import Foundation

/// App-level constants derived from the active account.
/// Falls back to "orchestrator" if no account is active (should not happen in normal use).
@MainActor
enum AppConstants {
    static var account: GatewayAccount?

    static var agentId: String { account?.agentId ?? "orchestrator" }
    static var workspaceRoot: String { account?.workspaceRoot ?? "~/.openclaw/workspace/orchestrator/" }
}

/// Well-known session keys — derived from the active account's agentId.
@MainActor
enum SessionKeys {
    static var main: String { AppConstants.account?.sessionKeyMain ?? "agent:orchestrator:main" }
    static var cronPrefix: String { AppConstants.account?.sessionKeyCronPrefix ?? "agent:orchestrator:cron:" }
    static var subagentPrefix: String { AppConstants.account?.sessionKeySubagentPrefix ?? "agent:orchestrator:subagent:" }
}

// MARK: - Gateway Response Wrapper

/// Actual envelope: {"ok":true,"result":{"content":[{"type":"text","text":"<json string>"}]}}
struct GatewayResponse: Decodable, Sendable {
    struct Result: Decodable, Sendable {
        struct Content: Decodable, Sendable {
            let type: String
            let text: String
        }
        let content: [Content]
    }
    let ok: Bool
    let result: Result
}

// MARK: - Gateway Tool Request

struct GatewayToolRequest: Encodable, Sendable {
    let tool = "gateway"
    let args: Args

    struct Args: Encodable, Sendable {
        let action: String
    }
}

// MARK: - Error Types

struct GatewayErrorEnvelope: Decodable, Sendable {
    struct ErrorDetail: Decodable, Sendable {
        let type: String
        let message: String
    }
    let ok: Bool
    let error: ErrorDetail?
}

enum GatewayError: LocalizedError {
    case noToken
    case noBaseURL
    case invalidResponse
    case httpError(Int, body: String)
    case serverError(Int, type: String, message: String)
    case emptyContent
    case connectionLost

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "未配置认证 Token。请先到设置中添加 Bearer Token。"
        case .noBaseURL:
            return "未配置网关地址。请到设置中填写网关地址。"
        case .invalidResponse:
            return "网关返回了无效响应。"
        case .httpError(let code, let body):
            return "网关 HTTP \(code)。响应内容：\(body.isEmpty ? "（空）" : body)"
        case .serverError(let code, _, let message):
            return "网关 HTTP \(code)：\(message)"
        case .emptyContent:
            return "网关返回了空响应。"
        case .connectionLost:
            return "连接已断开——服务器上的任务可能仍在继续执行，请稍后再查看。"
        }
    }
}

// MARK: - Gateway Command Response

/// Response from a gateway tool command (e.g. restart).
struct GatewayCommandResponse: Decodable, Sendable {
    let message: String?
    let text: String?
}
