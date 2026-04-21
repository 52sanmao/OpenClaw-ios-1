import Foundation
import Observation

@Observable
@MainActor
final class AdminViewModel {
    // Inference
    var providers: [LLMProviderDTO] = []
    var selectedModel: String?
    var selectedBackendId: String?
    var customProviders: [LLMProviderDTO] = []
    var customProviderDTOs: [LLMCustomProviderDTO] = []
    var builtinOverrides: [String: LLMBuiltinOverrideDTO] = [:]
    var modelsConfig: ModelsConfig?

    // Agent (orchestrator)
    var agent: AgentProfile?
    var profile: UserProfileDTO?

    // Channels
    var channelsStatus: ChannelsStatus?
    var installedExtensions: [ExtensionInfoDTO] = []
    var extensionsRegistry: [ExtensionRegistryEntryDTO] = []

    // Users
    var adminUsers: [AdminUserDTO] = []

    // Settings export (raw heterogeneous map)
    var settingsExport: [String: JSONValue]? = nil

    var isLoading = false
    var error: Error?

    /// Legacy surface kept so existing views (e.g. ModelsSection) still compile.
    /// We now expose an empty agents array by default — "代理" page shows the
    /// orchestrator via the new `agent` property.
    var agents: [AgentInfo] = []

    private let client: GatewayClientProtocol

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        AppLogStore.shared.append("AdminViewModel: 开始加载 REST 聚合")

        // Parallel fetch — individual failures are tolerated.
        async let providersTask: [LLMProviderDTO]? = try? client.stats("api/llm/providers")
        async let extensionsTask: ExtensionListResponseDTO? = try? client.stats("api/extensions")
        async let registryTask: ExtensionRegistryResponseDTO? = try? client.stats("api/extensions/registry")
        async let settingsTask: SettingsExportResponseDTO? = try? client.stats("api/settings/export")
        async let profileTask: UserProfileDTO? = try? client.stats("api/profile")
        async let usersTask: AdminUsersResponseDTO? = try? client.stats("api/admin/users")

        let providersFetched = await providersTask ?? []
        let extensionsFetched = (await extensionsTask)?.extensions ?? []
        let registryFetched = (await registryTask)?.entries ?? []
        let settingsFetched = (await settingsTask)?.settings ?? [:]
        let profileFetched = await profileTask
        let usersFetched = (await usersTask)?.users ?? []

        AppLogStore.shared.append("AdminViewModel: REST providers=\(providersFetched.count) ext=\(extensionsFetched.count) registry=\(registryFetched.count) users=\(usersFetched.count)")

        if providersFetched.isEmpty && extensionsFetched.isEmpty && settingsFetched.isEmpty {
            AppLogStore.shared.append("AdminViewModel: REST 无数据，尝试 stats/exec 回退")
            await loadLegacyStatsExec()
            return
        }

        applyRest(
            providers: providersFetched,
            extensions: extensionsFetched,
            registry: registryFetched,
            settings: settingsFetched,
            profile: profileFetched,
            users: usersFetched
        )
    }

    var unavailableDescription: String {
        "这些页面依赖 /api/llm/providers、/api/extensions、/api/settings/export 等 REST 接口。当前网关未返回数据；聊天主链路与 routines 不受影响。"
    }

    // MARK: - REST mapping

    private func applyRest(
        providers: [LLMProviderDTO],
        extensions: [ExtensionInfoDTO],
        registry: [ExtensionRegistryEntryDTO],
        settings: [String: JSONValue],
        profile: UserProfileDTO?,
        users: [AdminUserDTO]
    ) {
        self.providers = providers
        self.installedExtensions = extensions
        self.extensionsRegistry = registry
        self.profile = profile
        self.adminUsers = users
        self.settingsExport = settings

        // Selected model / backend from settings
        self.selectedModel = settings["selected_model"]?.stringValue
        self.selectedBackendId = settings["llm_backend"]?.stringValue

        // Custom providers from settings.llm_custom_providers — keep both the
        // UI-facing LLMProviderDTO shape (for the provider list) and the
        // source-of-truth LLMCustomProviderDTO array (for save round-trip).
        if let custom = settings["llm_custom_providers"]?.arrayValue {
            self.customProviders = custom.compactMap { value -> LLMProviderDTO? in
                guard let obj = value.objectValue else { return nil }
                return LLMProviderDTO(
                    id: obj["id"]?.stringValue ?? "",
                    name: obj["name"]?.stringValue ?? "未命名",
                    adapter: obj["adapter"]?.stringValue,
                    baseUrl: obj["base_url"]?.stringValue,
                    builtin: false,
                    defaultModel: obj["default_model"]?.stringValue,
                    apiKeyRequired: true,
                    canListModels: nil,
                    hasApiKey: (obj["api_key"]?.stringValue?.isEmpty == false),
                    envModel: nil,
                    envBaseUrl: nil
                )
            }
            self.customProviderDTOs = custom.compactMap { value -> LLMCustomProviderDTO? in
                guard let obj = value.objectValue else { return nil }
                return LLMCustomProviderDTO(
                    id: obj["id"]?.stringValue ?? "",
                    name: obj["name"]?.stringValue ?? "",
                    adapter: obj["adapter"]?.stringValue ?? "open_ai_completions",
                    baseUrl: obj["base_url"]?.stringValue,
                    defaultModel: obj["default_model"]?.stringValue,
                    apiKey: obj["api_key"]?.stringValue,
                    builtin: false
                )
            }
        } else {
            self.customProviders = []
            self.customProviderDTOs = []
        }

        // Builtin overrides (per-provider api_key / model / base_url)
        if let overrides = settings["llm_builtin_overrides"]?.objectValue {
            var map: [String: LLMBuiltinOverrideDTO] = [:]
            for (id, v) in overrides {
                guard let obj = v.objectValue else { continue }
                map[id] = LLMBuiltinOverrideDTO(
                    apiKey: obj["api_key"]?.stringValue,
                    model: obj["model"]?.stringValue,
                    baseUrl: obj["base_url"]?.stringValue
                )
            }
            self.builtinOverrides = map
        } else {
            self.builtinOverrides = [:]
        }

        // Models config (for legacy code that still reads it)
        let configured = providers.filter { $0.hasApiKey == true }
        let primary = selectedBackendId.flatMap { id in providers.first { $0.id == id } }
            ?? configured.first
            ?? providers.first
        let defaultModel = self.selectedModel
            ?? primary.flatMap { $0.envModel ?? $0.defaultModel }
            ?? "unknown"
        let fallbackModels = configured
            .filter { $0.id != primary?.id }
            .compactMap { $0.envModel ?? $0.defaultModel }
            .filter { !$0.isEmpty }
        self.modelsConfig = ModelsConfig(
            defaultModel: defaultModel,
            fallbacks: fallbackModels,
            imageModel: nil,
            aliases: providers.compactMap { p in
                guard let m = p.envModel ?? p.defaultModel, !m.isEmpty else { return nil }
                return (name: p.name, model: m)
            }.sorted { $0.name < $1.name }
        )

        // Agent (orchestrator profile) derived from /api/profile + settings
        let activatedChannels: [String] = (settings["activated_channels"]?.arrayValue ?? [])
            .compactMap { $0.stringValue }
        let autoApprove = settings["agent.auto_approve_tools"]?.boolValue ?? false
        let usePlanning = settings["agent.use_planning"]?.boolValue ?? false
        let allowLocalTools = settings["agent.allow_local_tools"]?.boolValue ?? false
        let agentId = profile?.id ?? "default"
        let agentName = profile?.displayName ?? agentId
        self.agent = AgentProfile(
            id: agentId,
            displayName: agentName,
            role: profile?.role ?? "agent",
            email: profile?.email,
            status: profile?.status ?? "active",
            model: defaultModel,
            activatedChannels: activatedChannels,
            autoApproveTools: autoApprove,
            usePlanning: usePlanning,
            allowLocalTools: allowLocalTools
        )

        // Channels — ONLY from /api/extensions filtered by channel kinds + pairing.
        // NOTE: removed the erroneous "providers as channels" mapping; providers
        // belong to the 推理 page.
        let channelExts = extensions.filter { ext in
            let k = ext.kind.lowercased()
            return k == "wasm_channel" || k == "channel_relay"
        }
        let channelList: [ChannelsStatus.Channel] = channelExts.map { ext in
            ChannelsStatus.Channel(
                id: ext.name,
                name: ext.displayName ?? ext.name.capitalized,
                isConnected: (ext.activationStatus?.lowercased() == "active") || (ext.active && ext.authenticated),
                accountCount: ext.authenticated ? 1 : 0
            )
        }
        self.channelsStatus = ChannelsStatus(channels: channelList, providers: [])
    }

    // MARK: - Legacy fallback

    private func loadLegacyStatsExec() async {
        do {
            let response: StatsExecResponse = try await client.statsPost(
                "stats/exec", body: StatsExecRequest(command: "models-status")
            )
            if let data = response.stdout?.data(using: .utf8) {
                let dto = try JSONDecoder().decode(ModelsStatusDTO.self, from: data)
                modelsConfig = ModelsConfig(dto: dto)
            }
        } catch {
            if modelsConfig == nil { self.error = error }
        }
    }

    // MARK: - Actions

    func testConnection(for provider: LLMProviderDTO) async -> LLMTestConnectionResponse {
        let body = LLMTestConnectionRequest(
            adapter: provider.adapter ?? "open_ai_completions",
            baseUrl: provider.envBaseUrl ?? provider.baseUrl ?? "",
            model: provider.envModel ?? provider.defaultModel ?? "default",
            providerId: provider.id,
            providerType: provider.builtin == false ? "custom" : "builtin"
        )
        do {
            return try await client.statsPost("api/llm/test_connection", body: body)
        } catch {
            return LLMTestConnectionResponse(ok: false, message: error.localizedDescription)
        }
    }

    func testConnectionRaw(_ body: LLMTestConnectionRequest) async throws -> LLMTestConnectionResponse {
        try await client.statsPost("api/llm/test_connection", body: body)
    }

    func listModels(for provider: LLMProviderDTO) async -> LLMListModelsResponse {
        let body = LLMListModelsRequest(
            adapter: provider.adapter ?? "open_ai_completions",
            baseUrl: provider.envBaseUrl ?? provider.baseUrl ?? "",
            providerId: provider.id,
            providerType: provider.builtin == false ? "custom" : "builtin"
        )
        do {
            return try await client.statsPost("api/llm/list_models", body: body)
        } catch {
            return LLMListModelsResponse(ok: false, message: error.localizedDescription, models: [])
        }
    }

    func listModelsRaw(_ body: LLMListModelsRequest) async throws -> LLMListModelsResponse {
        try await client.statsPost("api/llm/list_models", body: body)
    }

    func builtinOverride(for id: String) -> LLMBuiltinOverrideDTO? {
        builtinOverrides[id]
    }

    /// Remove a custom provider by id. Refuses to remove the currently active
    /// provider — caller must switch first.
    func removeCustomProvider(id: String) async throws {
        guard id != selectedBackendId else {
            throw NSError(domain: "Admin", code: 409, userInfo: [NSLocalizedDescriptionKey: "不能删除当前使用中的 Provider"])
        }
        let updated = customProviderDTOs.filter { $0.id != id }
        try await saveCustomProviders(updated)
    }

    func installExtension(name: String, kind: String?) async throws {
        let body = ExtensionInstallRequest(name: name, kind: kind, url: nil)
        let _: ExtensionActionResponse = try await client.statsPost("api/extensions/install", body: body)
        await load()
    }

    func removeExtension(name: String) async throws {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let _: ExtensionActionResponse = try await client.statsPost("api/extensions/\(encoded)/remove", body: EmptyBody())
        await load()
    }

    func activateExtension(name: String) async throws -> ExtensionActivateResponseDTO {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let res: ExtensionActivateResponseDTO = try await client.statsPost(
            "api/extensions/\(encoded)/activate", body: EmptyBody()
        )
        await load()
        return res
    }

    func loadExtensionSetup(name: String) async throws -> ExtensionSetupResponseDTO {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return try await client.stats("api/extensions/\(encoded)/setup")
    }

    func submitExtensionSetup(name: String, secrets: [String: String]) async throws -> ExtensionSetupResponseDTO {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let body = ExtensionSetupRequest(secrets: secrets, fields: [:])
        let res: ExtensionSetupResponseDTO = try await client.statsPost("api/extensions/\(encoded)/setup", body: body)
        await load()
        return res
    }

    // MARK: - Admin users

    @discardableResult
    func createUser(displayName: String, email: String?, role: String) async throws -> CreateTokenResponse? {
        let body = AdminUserCreateRequest(
            displayName: displayName,
            email: (email?.isEmpty == false) ? email : nil,
            role: role
        )
        let response: CreateTokenResponse = try await client.statsPost("api/admin/users", body: body)
        await load()
        return response.effectiveToken != nil ? response : nil
    }

    func suspendUser(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        try await client.statsPostVoid("api/admin/users/\(encoded)/suspend")
        await load()
    }

    func activateUser(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        try await client.statsPostVoid("api/admin/users/\(encoded)/activate")
        await load()
    }

    func setUserRole(id: String, role: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: AdminUserDTO = try await client.statsPatch(
            "api/admin/users/\(encoded)", body: AdminUserPatchRequest(role: role, status: nil, displayName: nil)
        )
        await load()
    }

    func deleteUser(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        try await client.statsDeleteVoid("api/admin/users/\(encoded)")
        await load()
    }

    func createToken(userId: String, name: String) async throws -> String? {
        let body = CreateTokenRequest(name: name, userId: userId)
        let res: CreateTokenResponse = try await client.statsPost("api/tokens", body: body)
        return res.effectiveToken
    }

    func loadUserDetail(id: String) async throws -> AdminUserDTO {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await client.stats("api/admin/users/\(encoded)")
    }

    func loadUserUsage(userId: String, period: String = "month") async throws -> AdminUsageResponseDTO {
        let encodedUser = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId
        return try await client.stats("api/admin/usage?user_id=\(encodedUser)&period=\(period)")
    }

    func loadAggregateUsage(period: String) async throws -> AdminUsageResponseDTO {
        return try await client.stats("api/admin/usage?period=\(period)")
    }

    func loadAdminSummary() async throws -> AdminUsageSummaryDTO {
        return try await client.stats("api/admin/usage/summary")
    }

    // MARK: - LLM backend / model settings

    func setActiveLLMBackend(id: String) async throws {
        try await client.statsPutVoid(
            "api/settings/llm_backend",
            body: SettingsValuePayload(value: id)
        )
        selectedBackendId = id
    }

    func setSelectedModel(_ model: String?) async throws {
        if let model {
            try await client.statsPutVoid(
                "api/settings/selected_model",
                body: SettingsValuePayload(value: model)
            )
        } else {
            try await client.statsDeleteVoid("api/settings/selected_model")
        }
        selectedModel = model
    }

    func saveCustomProviders(_ providers: [LLMCustomProviderDTO]) async throws {
        struct Payload: Encodable { let value: [LLMCustomProviderDTO] }
        let data = try JSONEncoder().encode(Payload(value: providers))
        try await client.statsPutVoidRaw("api/settings/llm_custom_providers", body: data)
        await load()
    }

    func saveBuiltinOverrides(_ overrides: [String: LLMBuiltinOverrideDTO]) async throws {
        struct Payload: Encodable { let value: [String: LLMBuiltinOverrideDTO] }
        let data = try JSONEncoder().encode(Payload(value: overrides))
        try await client.statsPutVoidRaw("api/settings/llm_builtin_overrides", body: data)
        await load()
    }

    func saveSetting<V: Encodable & Sendable>(key: String, value: V) async throws {
        try await client.statsPutVoid(
            "api/settings/\(key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key)",
            body: SettingsValuePayload(value: value)
        )
        await load()
    }

    // MARK: - Existing

    func loadPairing(channel: String) async throws -> PairingResponseDTO {
        let encoded = channel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? channel
        return try await client.stats("api/pairing/\(encoded)")
    }

    // MARK: - Settings export/import

    /// Fetch fresh settings export and return as pretty-printed JSON string.
    func exportSettingsJSON() async throws -> String {
        let dto: SettingsExportResponseDTO = try await client.stats("api/settings/export")
        let export = dto.settings ?? [:]
        self.settingsExport = export
        let wrapper: [String: Any] = ["settings": jsonValueToAny(export)]
        let data = try JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "AdminViewModel", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法编码导出数据"])
        }
        return string
    }

    /// POST a JSON string to /api/settings/import. Accepts either the full export wrapper
    /// `{ "settings": { ... } }` or just the inner settings map `{ ... }`.
    func importSettingsJSON(_ json: String) async throws {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            throw NSError(domain: "AdminViewModel", code: 400, userInfo: [NSLocalizedDescriptionKey: "JSON 解析失败"])
        }
        let body: Data
        if let wrapper = parsed as? [String: Any], wrapper["settings"] != nil {
            body = try JSONSerialization.data(withJSONObject: wrapper, options: [.sortedKeys])
        } else if let map = parsed as? [String: Any] {
            body = try JSONSerialization.data(withJSONObject: ["settings": map], options: [.sortedKeys])
        } else {
            throw NSError(domain: "AdminViewModel", code: 400, userInfo: [NSLocalizedDescriptionKey: "JSON 格式不正确，应为对象"])
        }
        try await client.statsPostVoidRaw("api/settings/import", body: body)
        await load()
    }
}

private func jsonValueToAny(_ value: JSONValue) -> Any {
    switch value {
    case .string(let s): return s
    case .int(let i): return i
    case .double(let d): return d
    case .bool(let b): return b
    case .array(let arr): return arr.map(jsonValueToAny)
    case .object(let obj): return obj.mapValues(jsonValueToAny)
    case .null: return NSNull()
    }
}

private func jsonValueToAny(_ dict: [String: JSONValue]) -> [String: Any] {
    dict.mapValues(jsonValueToAny)
}

// MARK: - Agent profile domain type

struct AgentProfile: Sendable {
    let id: String
    let displayName: String
    let role: String
    let email: String?
    let status: String
    let model: String
    let activatedChannels: [String]
    let autoApproveTools: Bool
    let usePlanning: Bool
    let allowLocalTools: Bool
}

// MARK: - Helpers

private struct EmptyBody: Encodable, Sendable {}
