import Foundation
import Observation

@Observable
@MainActor
final class AdminViewModel {
    var modelsConfig: ModelsConfig?
    var agents: [AgentInfo] = []
    var channelsStatus: ChannelsStatus?
    var isLoading = false
    var error: Error?

    private let client: GatewayClientProtocol

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        AppLogStore.shared.append("AdminViewModel: 开始加载（REST 优先 → stats/exec fallback）")

        // 1) Try real REST endpoints first (the Rust gateway actually exposes these).
        let providers: [LLMProviderDTO] = (try? await client.stats("api/llm/providers")) ?? []
        let extensionsEnvelope: ExtensionListResponseDTO? = try? await client.stats("api/extensions")
        let extensions = extensionsEnvelope?.extensions ?? []

        if !providers.isEmpty || !extensions.isEmpty {
            AppLogStore.shared.append("AdminViewModel: REST 成功 providers=\(providers.count) extensions=\(extensions.count)")
            applyRest(providers: providers, extensions: extensions)
            return
        }

        AppLogStore.shared.append("AdminViewModel: REST 无数据，尝试 stats/exec 回退")
        await loadLegacyStatsExec()
    }

    var unavailableDescription: String {
        "这些页面依赖 /api/llm/providers、/api/extensions 等 REST 接口，或历史 /stats/exec 管理命令。当前网关两者皆未返回数据，但聊天主链路与 routines 不受影响。"
    }

    // MARK: - Real REST mapping

    private func applyRest(providers: [LLMProviderDTO], extensions: [ExtensionInfoDTO]) {
        // Models — from /api/llm/providers
        let configured = providers.filter { $0.hasApiKey == true }
        let primary = configured.first ?? providers.first
        let defaultModel: String = primary.flatMap { $0.envModel ?? $0.defaultModel } ?? "unknown"
        let fallbackModels: [String] = configured
            .dropFirst()
            .compactMap { $0.envModel ?? $0.defaultModel }
            .filter { !$0.isEmpty }
        let aliasPairs: [(name: String, model: String)] = providers.compactMap { p in
            guard let model = p.envModel ?? p.defaultModel, !model.isEmpty else { return nil }
            return (name: p.name, model: model)
        }

        modelsConfig = ModelsConfig(
            defaultModel: defaultModel,
            fallbacks: fallbackModels,
            imageModel: nil,
            aliases: aliasPairs.sorted { $0.name < $1.name }
        )

        // Agents — IronClaw has no REST agents list; surface "providers as agents"
        // so the page remains informative instead of empty.
        var agentList: [AgentInfo] = []
        if let primary {
            agentList.append(
                AgentInfo(
                    id: "orchestrator",
                    name: "Orchestrator",
                    emoji: "🤖",
                    model: primary.envModel ?? primary.defaultModel,
                    isDefault: true
                )
            )
        }
        for provider in providers where provider.id != (primary?.id ?? "") {
            agentList.append(
                AgentInfo(
                    id: provider.id,
                    name: provider.name,
                    emoji: emoji(forProvider: provider.id),
                    model: provider.envModel ?? provider.defaultModel,
                    isDefault: false
                )
            )
        }
        agents = agentList

        // Channels — from /api/extensions where kind ∈ (wasm_channel, channel_relay)
        let channelExts = extensions.filter { ext in
            let k = ext.kind.lowercased()
            return k == "wasm_channel" || k == "channel_relay"
        }
        let channelList: [ChannelsStatus.Channel] = channelExts.map { ext in
            ChannelsStatus.Channel(
                id: ext.name,
                name: ext.displayName ?? ext.name.capitalized,
                isConnected: ext.active || ext.authenticated,
                accountCount: ext.authenticated ? 1 : 0
            )
        }
        let providerUsages: [ChannelsStatus.ProviderUsage] = providers.map { p in
            ChannelsStatus.ProviderUsage(
                id: p.id,
                displayName: p.name,
                plan: p.builtin == true ? "内置" : "自定义",
                windows: []
            )
        }
        channelsStatus = ChannelsStatus(channels: channelList, providers: providerUsages)
    }

    private func emoji(forProvider id: String) -> String {
        switch id.lowercased() {
        case "anthropic": return "🪶"
        case "openai":    return "🟢"
        case "nearai":    return "🌐"
        case "gemini":    return "💎"
        case "ollama":    return "🦙"
        case "bedrock":   return "🟧"
        default:          return "🤖"
        }
    }

    // MARK: - Legacy fallback

    private func loadLegacyStatsExec() async {
        await loadModelsLegacy()
        await loadAgentsLegacy()
        await loadChannelsLegacy()
    }

    private func loadModelsLegacy() async {
        do {
            let response: StatsExecResponse = try await client.statsPost(
                "stats/exec", body: StatsExecRequest(command: "models-status")
            )
            if let data = response.stdout?.data(using: .utf8) {
                let dto = try JSONDecoder().decode(ModelsStatusDTO.self, from: data)
                modelsConfig = ModelsConfig(dto: dto)
            }
        } catch {
            AppLogStore.shared.append("AdminViewModel: models-status 回退失败 \(error.localizedDescription)")
            if modelsConfig == nil { self.error = error }
        }
    }

    private func loadAgentsLegacy() async {
        do {
            let response: StatsExecResponse = try await client.statsPost(
                "stats/exec", body: StatsExecRequest(command: "agents-list")
            )
            if let data = response.stdout?.data(using: .utf8) {
                let dtos = try JSONDecoder().decode([AgentDTO].self, from: data)
                agents = dtos.map(AgentInfo.init)
            }
        } catch {
            AppLogStore.shared.append("AdminViewModel: agents-list 回退失败 \(error.localizedDescription)")
            if agents.isEmpty { self.error = error }
        }
    }

    private func loadChannelsLegacy() async {
        do {
            let response: StatsExecResponse = try await client.statsPost(
                "stats/exec", body: StatsExecRequest(command: "channels-list")
            )
            if let data = response.stdout?.data(using: .utf8) {
                let dto = try JSONDecoder().decode(ChannelsListDTO.self, from: data)
                channelsStatus = ChannelsStatus(dto: dto)
            }
        } catch {
            AppLogStore.shared.append("AdminViewModel: channels-list 回退失败 \(error.localizedDescription)")
            if channelsStatus == nil { self.error = error }
        }
    }
}
