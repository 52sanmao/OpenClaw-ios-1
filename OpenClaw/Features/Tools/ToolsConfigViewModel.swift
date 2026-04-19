import Foundation
import Observation

@Observable
@MainActor
final class ToolsConfigViewModel {
    var config: ToolsConfig?
    var mcpServers: [McpServer] = []
    var mcpDetails: [String: McpServerDetail] = [:]
    var isLoading = false
    var isLoadingMcpTools = false
    var error: Error?

    private let client: GatewayClientProtocol

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        AppLogStore.shared.append("ToolsConfigViewModel: 开始加载（REST 优先 → stats/exec fallback）")

        // 1) Try real REST endpoints first.
        let toolsEnvelope: ExtensionToolListResponseDTO? = try? await client.stats("api/extensions/tools")
        let extensionsEnvelope: ExtensionListResponseDTO? = try? await client.stats("api/extensions")
        let permissionsEnvelope: ToolPermissionsResponseDTO? = try? await client.stats("api/settings/tools")

        let allTools = toolsEnvelope?.tools ?? []
        let extensions = extensionsEnvelope?.extensions ?? []

        if !allTools.isEmpty || !extensions.isEmpty {
            AppLogStore.shared.append("ToolsConfigViewModel: REST 成功 tools=\(allTools.count) extensions=\(extensions.count) permissions=\(permissionsEnvelope?.tools.count ?? 0)")
            applyRest(
                tools: allTools,
                extensions: extensions,
                permissions: permissionsEnvelope?.tools ?? []
            )
            return
        }

        AppLogStore.shared.append("ToolsConfigViewModel: REST 无数据，尝试 stats/exec 回退")
        await loadLegacyStatsExec()
    }

    var unavailableDescription: String {
        "此页面依赖 /api/extensions、/api/extensions/tools、/api/settings/tools（或历史 /stats/exec）。当前网关均未返回，但聊天主链路与 routines 不受影响。"
    }

    /// Lazy load — kept for compatibility; REST path populates mcpDetails inline.
    func loadMcpTools() async {
        guard !isLoadingMcpTools && mcpDetails.isEmpty else { return }
        isLoadingMcpTools = true
        defer { isLoadingMcpTools = false }

        if let envelope: ExtensionListResponseDTO = try? await client.stats("api/extensions") {
            applyMcpFromRest(envelope.extensions)
            if !mcpDetails.isEmpty { return }
        }

        do {
            AppLogStore.shared.append("ToolsConfigViewModel: 开始读取 mcp-tools（fallback）")
            let response: StatsExecResponse = try await client.statsPost(
                "stats/exec", body: StatsExecRequest(command: "mcp-tools")
            )
            if let data = response.stdout?.data(using: .utf8) {
                let dto = try JSONDecoder().decode(McpToolsDTO.self, from: data)
                for (name, serverTools) in dto.servers {
                    mcpDetails[name] = McpServerDetail(
                        status: serverTools.status,
                        tools: serverTools.tools ?? [],
                        error: serverTools.error
                    )
                }
            }
        } catch {
            AppLogStore.shared.append("ToolsConfigViewModel: mcp-tools 回退失败 \(error.localizedDescription)")
        }
    }

    // MARK: - REST mapping

    private func applyRest(
        tools: [ExtensionToolDTO],
        extensions: [ExtensionInfoDTO],
        permissions: [ToolPermissionEntryDTO]
    ) {
        let allowList = permissions.filter { $0.currentState == "allow_always" }.map { $0.name }.sorted()
        let denyList = permissions.filter { $0.currentState == "deny_always" }.map { $0.name }.sorted()

        let grouped = Dictionary(grouping: tools, by: { groupKey(for: $0.name) })

        let iconMap: [String: (name: String, icon: String)] = [
            "runtime":    ("运行时",   "terminal"),
            "file":       ("文件",     "doc.text"),
            "web":        ("网络",     "globe"),
            "ui":         ("界面",     "macwindow"),
            "messaging":  ("消息",     "message"),
            "schedule":   ("自动化",   "clock.arrow.circlepath"),
            "memory":     ("记忆",     "brain"),
            "session":    ("会话",     "person.2"),
            "skill":      ("技能",     "bolt.circle"),
            "settings":   ("设置",     "slider.horizontal.3"),
            "thread":     ("线程",     "text.bubble"),
            "other":      ("其他",     "puzzlepiece")
        ]

        let groups: [ToolsConfig.ToolGroup] = grouped.keys.sorted().map { key in
            let info = iconMap[key] ?? (name: key.capitalized, icon: "puzzlepiece")
            let items = (grouped[key] ?? []).map { tool in
                ToolsConfig.NativeTool(id: tool.name, name: tool.name, description: tool.description ?? "")
            }
            return ToolsConfig.ToolGroup(id: key, name: info.name, icon: info.icon, tools: items)
        }

        let profile: String = inferProfile(permissions: permissions)
        let mcpNames = extensions.filter { $0.kind.lowercased() == "mcp_server" }.map(\.name)

        config = ToolsConfig(
            profile: profile,
            allow: allowList,
            deny: denyList,
            mcpServerNames: mcpNames,
            groups: groups
        )

        applyMcpFromRest(extensions)
    }

    private func applyMcpFromRest(_ extensions: [ExtensionInfoDTO]) {
        let mcp = extensions.filter { $0.kind.lowercased() == "mcp_server" }
        mcpServers = mcp
            .map { McpServer(name: $0.name, runtime: $0.url ?? $0.displayName ?? "mcp") }
            .sorted { $0.name < $1.name }

        var details: [String: McpServerDetail] = [:]
        for ext in mcp {
            details[ext.name] = McpServerDetail(
                status: ext.active ? "ok" : (ext.activationStatus?.lowercased() ?? "stopped"),
                tools: (ext.tools ?? []).map { McpToolsDTO.Tool(name: $0, description: nil) },
                error: ext.activationError
            )
        }
        mcpDetails = details
    }

    private func groupKey(for toolName: String) -> String {
        let lower = toolName.lowercased()
        if let prefix = lower.components(separatedBy: "_").first, !prefix.isEmpty {
            let known: Set<String> = [
                "runtime", "file", "web", "ui", "messaging",
                "schedule", "memory", "session", "skill", "settings", "thread"
            ]
            if known.contains(prefix) { return prefix }
        }
        return "other"
    }

    private func inferProfile(permissions: [ToolPermissionEntryDTO]) -> String {
        let allowCount = permissions.filter { $0.currentState == "allow_always" }.count
        let totalCount = permissions.count
        if totalCount == 0 { return "unknown" }
        let ratio = Double(allowCount) / Double(totalCount)
        if ratio >= 0.8 { return "full" }
        if ratio >= 0.4 { return "coding" }
        if ratio >= 0.15 { return "messaging" }
        return "minimal"
    }

    // MARK: - Legacy fallback

    private func loadLegacyStatsExec() async {
        do {
            let response: StatsExecResponse = try await client.statsPost(
                "stats/exec", body: StatsExecRequest(command: "tools-list")
            )
            if let data = response.stdout?.data(using: .utf8) {
                config = ToolsConfig(dto: try JSONDecoder().decode(ToolsListDTO.self, from: data))
            }
        } catch let gatewayError as GatewayError {
            AppLogStore.shared.append("ToolsConfigViewModel: tools-list 回退失败 \(gatewayError.localizedDescription)")
            if case .httpError(404, _) = gatewayError {
                self.error = gatewayError
                return
            }
            self.error = gatewayError
        } catch {
            AppLogStore.shared.append("ToolsConfigViewModel: tools-list 回退失败 \(error.localizedDescription)")
            self.error = error
        }

        do {
            let response: StatsExecResponse = try await client.statsPost(
                "stats/exec", body: StatsExecRequest(command: "mcp-list")
            )
            if let data = response.stdout?.data(using: .utf8) {
                let dto = try JSONDecoder().decode(McpListDTO.self, from: data)
                mcpServers = dto.servers.map { McpServer(name: $0.key, config: $0.value) }.sorted { $0.name < $1.name }
            }
        } catch {
            AppLogStore.shared.append("ToolsConfigViewModel: mcp-list 回退失败 \(error.localizedDescription)")
        }
    }
}
