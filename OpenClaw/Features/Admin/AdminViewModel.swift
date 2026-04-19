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

        // Selected model / backend from settings
        self.selectedModel = settings["selected_model"]?.stringValue
        self.selectedBackendId = settings["llm_backend"]?.stringValue

        // Custom providers from settings.llm_custom_providers
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
        } else {
            self.customProviders = []
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

    func createUser(displayName: String, role: String) async throws {
        let body = AdminUserCreateRequest(displayName: displayName, role: role)
        let _: AdminUserDTO = try await client.statsPost("api/admin/users", body: body)
        await load()
    }
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
