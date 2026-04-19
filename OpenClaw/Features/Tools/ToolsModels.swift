import Foundation
import SwiftUI

struct ToolsConfig: Sendable {
    let profile: String
    let allow: [String]
    let deny: [String]
    let mcpServerNames: [String]
    let groups: [ToolGroup]

    struct ToolGroup: Sendable, Identifiable {
        let id: String
        let name: String
        let icon: String
        let tools: [NativeTool]
    }

    struct NativeTool: Sendable, Identifiable {
        let id: String
        let name: String
        let description: String
    }

    var profileColor: Color {
        switch profile {
        case "full":      AppColors.success
        case "coding":    AppColors.primaryAction
        case "messaging": AppColors.metricTertiary
        case "minimal":   AppColors.metricWarm
        default:          AppColors.neutral
        }
    }

    init(dto: ToolsListDTO) {
        profile = dto.profile ?? "unknown"
        allow = dto.allow ?? []
        deny = dto.deny ?? []
        mcpServerNames = dto.mcpServers ?? []

        let iconMap: [String: (name: String, icon: String)] = [
            "runtime":    ("运行时",    "terminal"),
            "fs":         ("文件",      "doc.text"),
            "web":        ("网络",      "globe"),
            "ui":         ("界面",      "macwindow"),
            "messaging":  ("消息",      "message"),
            "automation": ("自动化",    "clock.arrow.circlepath"),
            "nodes":      ("节点",      "iphone.radiowaves.left.and.right"),
            "media":      ("媒体",      "photo"),
            "sessions":   ("会话",      "person.2"),
            "memory":     ("记忆",      "brain"),
        ]

        var grouped: [String: [NativeTool]] = [:]
        for tool in dto.native ?? [] {
            let group = tool.group ?? "other"
            grouped[group, default: []].append(
                NativeTool(id: tool.name, name: tool.name, description: tool.description ?? "")
            )
        }

        groups = grouped.keys.sorted().map { key in
            let info = iconMap[key] ?? (name: key.capitalized, icon: "puzzlepiece")
            return ToolGroup(id: key, name: info.name, icon: info.icon, tools: grouped[key] ?? [])
        }
    }

    init(profile: String, allow: [String], deny: [String], mcpServerNames: [String], groups: [ToolGroup]) {
        self.profile = profile
        self.allow = allow
        self.deny = deny
        self.mcpServerNames = mcpServerNames
        self.groups = groups
    }
}

struct McpServer: Sendable, Identifiable {
    let id: String
    let name: String
    let runtime: String

    init(name: String, config: McpListDTO.ServerConfig) {
        self.id = name
        self.name = name
        let args = config.args?.joined(separator: " ") ?? ""
        self.runtime = [config.command, args].filter { !($0 ?? "").isEmpty }.compactMap { $0 }.joined(separator: " ")
    }

    init(name: String, runtime: String) {
        self.id = name
        self.name = name
        self.runtime = runtime
    }
}

struct McpServerDetail: Sendable {
    let status: String
    let tools: [McpToolsDTO.Tool]
    let error: String?

    var isOk: Bool { status == "ok" }

    var statusColor: Color {
        switch status {
        case "ok": AppColors.success
        case "timeout": AppColors.warning
        default: AppColors.danger
        }
    }
}
