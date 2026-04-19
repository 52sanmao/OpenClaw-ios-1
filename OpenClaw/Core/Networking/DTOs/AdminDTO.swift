import Foundation

// MARK: - Models Status (legacy — kept for backward compatibility with stats/exec fallback)

struct ModelsStatusDTO: Decodable, Sendable {
    let defaultModel: String?
    let resolvedDefault: String?
    let fallbacks: [String]?
    let imageModel: String?
    let aliases: [String: String]?
}

// MARK: - Agents List (legacy — kept for backward compatibility)

struct AgentDTO: Decodable, Sendable {
    let id: String
    let name: String?
    let identityName: String?
    let identityEmoji: String?
    let model: String?
    let isDefault: Bool?
}

// MARK: - Channels List (legacy — kept for backward compatibility)

struct ChannelsListDTO: Decodable, Sendable {
    let chat: [String: [String]]?
    let usage: UsageInfo?

    struct UsageInfo: Decodable, Sendable {
        let updatedAt: Int?
        let providers: [ProviderUsage]?
    }

    struct ProviderUsage: Decodable, Sendable {
        let provider: String
        let displayName: String?
        let plan: String?
        let windows: [UsageWindow]?
    }

    struct UsageWindow: Decodable, Sendable {
        let label: String
        let usedPercent: Double
    }
}

// MARK: - /api/llm/providers (real REST)

struct LLMProviderDTO: Decodable, Sendable {
    let id: String
    let name: String
    let adapter: String?
    let baseUrl: String?
    let builtin: Bool?
    let defaultModel: String?
    let apiKeyRequired: Bool?
    let canListModels: Bool?
    let hasApiKey: Bool?
    let envModel: String?
    let envBaseUrl: String?
}

// MARK: - /api/llm/test_connection

struct LLMTestConnectionRequest: Encodable, Sendable {
    let adapter: String
    let baseUrl: String
    let model: String
    let providerId: String
    let providerType: String

    enum CodingKeys: String, CodingKey {
        case adapter
        case baseUrl = "base_url"
        case model
        case providerId = "provider_id"
        case providerType = "provider_type"
    }
}

struct LLMTestConnectionResponse: Decodable, Sendable {
    let ok: Bool
    let message: String
}

// MARK: - /api/llm/list_models

struct LLMListModelsRequest: Encodable, Sendable {
    let adapter: String
    let baseUrl: String
    let providerId: String
    let providerType: String

    enum CodingKeys: String, CodingKey {
        case adapter
        case baseUrl = "base_url"
        case providerId = "provider_id"
        case providerType = "provider_type"
    }
}

struct LLMListModelsResponse: Decodable, Sendable {
    let ok: Bool
    let message: String
    let models: [String]
}

// MARK: - /api/extensions (installed)

struct ExtensionListResponseDTO: Decodable, Sendable {
    let extensions: [ExtensionInfoDTO]
}

struct ExtensionInfoDTO: Decodable, Sendable {
    let name: String
    let displayName: String?
    let kind: String              // wasm_channel | channel_relay | mcp_server | wasm_tool | acp_agent
    let description: String?
    let url: String?
    let authenticated: Bool
    let active: Bool
    let tools: [String]?
    let needsSetup: Bool?
    let hasAuth: Bool?
    let activationStatus: String?
    let activationError: String?
    let version: String?
    let onboardingState: String?
    let onboarding: ExtensionOnboardingDTO?
}

// Onboarding copy for channel-like extensions (Telegram, Discord, etc.)
struct ExtensionOnboardingDTO: Decodable, Sendable {
    let requiresPairing: Bool?
    let credentialTitle: String?
    let credentialInstructions: String?
    let credentialNextStep: String?
    let setupUrl: String?
    let pairingTitle: String?
    let pairingInstructions: String?
}

// MARK: - /api/extensions/{name}/setup  (GET + POST)

struct ExtensionSetupResponseDTO: Decodable, Sendable {
    let secrets: [ExtensionSecretFieldDTO]?
    let onboarding: ExtensionOnboardingDTO?
    let success: Bool?
    let message: String?
    let onboardingState: String?
    let authUrl: String?
}

struct ExtensionSecretFieldDTO: Decodable, Sendable {
    let name: String
    let label: String?
    let description: String?
    let type: String?           // "password" | "text" (default text)
    let placeholder: String?
    let required: Bool?
}

struct ExtensionSetupRequest: Encodable, Sendable {
    let secrets: [String: String]
    let fields: [String: String]
}

// MARK: - /api/extensions/{name}/activate

struct ExtensionActivateResponseDTO: Decodable, Sendable {
    let success: Bool?
    let message: String?
    let authUrl: String?
    let awaitingToken: Bool?
}

// MARK: - /api/extensions/registry (available to install)

struct ExtensionRegistryResponseDTO: Decodable, Sendable {
    let entries: [ExtensionRegistryEntryDTO]
}

struct ExtensionRegistryEntryDTO: Decodable, Sendable {
    let name: String
    let displayName: String?
    let kind: String
    let description: String?
    let keywords: [String]?
    let installed: Bool?
    let version: String?
}

// MARK: - /api/extensions/install & /api/extensions/{name}/remove

struct ExtensionInstallRequest: Encodable, Sendable {
    let name: String
    let kind: String?
    let url: String?
}

struct ExtensionActionResponse: Decodable, Sendable {
    let ok: Bool?
    let message: String?
}

// MARK: - /api/extensions/tools (legacy — kept for fallback)

struct ExtensionToolListResponseDTO: Decodable, Sendable {
    let tools: [ExtensionToolDTO]
}

struct ExtensionToolDTO: Decodable, Sendable {
    let name: String
    let description: String?
}

// MARK: - /api/settings/tools (legacy — kept for fallback)

struct ToolPermissionsResponseDTO: Decodable, Sendable {
    let tools: [ToolPermissionEntryDTO]
}

struct ToolPermissionEntryDTO: Decodable, Sendable {
    let name: String
    let description: String?
    let currentState: String
    let defaultState: String
    let locked: Bool
    let lockedReason: String?
}

// MARK: - /api/pairing/{channel}

struct PairingResponseDTO: Decodable, Sendable {
    let channel: String
    let requests: [PairingRequestDTO]?
}

struct PairingRequestDTO: Decodable, Sendable {
    let id: String?
    let userId: String?
    let status: String?
    let createdAt: String?
}

// MARK: - /api/profile

struct UserProfileDTO: Decodable, Sendable {
    let id: String
    let displayName: String?
    let email: String?
    let role: String?
    let status: String?
    let createdAt: String?
    let lastLoginAt: String?
}

// MARK: - /api/admin/users

struct AdminUsersResponseDTO: Decodable, Sendable {
    let users: [AdminUserDTO]
}

struct AdminUserDTO: Decodable, Sendable, Identifiable {
    let id: String
    let displayName: String?
    let email: String?
    let role: String?
    let status: String?
    let createdAt: String?
    let lastLoginAt: String?
    let lastActiveAt: String?
    let jobCount: Int?
    let totalCost: String?
}

struct AdminUserCreateRequest: Encodable, Sendable {
    let displayName: String
    let email: String?
    let role: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case email
        case role
    }
}

struct AdminUserPatchRequest: Encodable, Sendable {
    let role: String?
    let status: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case role
        case status
        case displayName = "display_name"
    }
}

// MARK: - /api/admin/usage  (aggregate usage)

struct AdminUsageResponseDTO: Decodable, Sendable {
    let usage: [AdminUsageEntryDTO]?
}

struct AdminUsageEntryDTO: Decodable, Sendable {
    let userId: String?
    let model: String
    let callCount: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalCost: String?
}

struct AdminUsageSummaryDTO: Decodable, Sendable {
    let users: UserCounts?
    let jobs: JobCounts?
    let usage30d: UsageTotals?
    let uptimeSeconds: Int?

    struct UserCounts: Decodable, Sendable {
        let total: Int?
        let active: Int?
        let suspended: Int?
        let admins: Int?
    }
    struct JobCounts: Decodable, Sendable {
        let total: Int?
    }
    struct UsageTotals: Decodable, Sendable {
        let llmCalls: Int?
        let totalCost: String?
    }

    enum CodingKeys: String, CodingKey {
        case users
        case jobs
        case usage30d = "usage_30d"
        case uptimeSeconds = "uptime_seconds"
    }
}

// MARK: - /api/tokens  (admin-issued tokens)

struct CreateTokenRequest: Encodable, Sendable {
    let name: String
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case name
        case userId = "user_id"
    }
}

struct CreateTokenResponse: Decodable, Sendable {
    let token: String?
    let plaintextToken: String?
    var effectiveToken: String? { token ?? plaintextToken }
}

// MARK: - /api/settings/{key}  (PUT/DELETE)

struct SettingsValuePayload<V: Encodable & Sendable>: Encodable, Sendable {
    let value: V
}

// LLM builtin override object (vaulted per-provider override).
struct LLMBuiltinOverrideDTO: Sendable {
    var apiKey: String?
    var model: String?
    var baseUrl: String?

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case model
        case baseUrl = "base_url"
    }
}
extension LLMBuiltinOverrideDTO: Codable {}

struct LLMCustomProviderDTO: Sendable, Identifiable {
    let id: String
    let name: String
    let adapter: String
    let baseUrl: String?
    let defaultModel: String?
    let apiKey: String?
    let builtin: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case adapter
        case baseUrl = "base_url"
        case defaultModel = "default_model"
        case apiKey = "api_key"
        case builtin
    }
}
extension LLMCustomProviderDTO: Codable {}

// Sentinel that tells the backend "keep the existing encrypted key".
enum LLMKeySentinel {
    static let unchanged = "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
}

// MARK: - /api/settings/export  (everything in one blob)

struct SettingsExportResponseDTO: Decodable, Sendable {
    /// Settings is a heterogeneous JSON map; preserve raw values for later unpacking.
    let settings: [String: JSONValue]?
}

// MARK: - JSONValue helper (for heterogeneous settings map)

enum JSONValue: Decodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        self = .null
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        if case .string(let s) = self { return ["true","1","yes"].contains(s.lowercased()) }
        return nil
    }
    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
}

// MARK: - /api/gateway/status

struct GatewayStatusDTO: Decodable, Sendable {
    let status: String?
    let version: String?
    let ready: Bool?
}
