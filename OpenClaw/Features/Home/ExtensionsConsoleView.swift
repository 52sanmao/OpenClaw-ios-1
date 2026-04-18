import SwiftUI

struct ExtensionsConsoleView: View {
    let vm: ToolsConfigViewModel

    var body: some View {
        List {
            Section("扩展概览") {
                HomeDetailRow(title: "配置档", value: vm.config?.profile.capitalized ?? "未加载")
                HomeDetailRow(title: "原生工具组", value: "\(vm.config?.groups.count ?? 0)")
                HomeDetailRow(title: "MCP 服务器", value: "\(vm.mcpServers.count)")
            }

            if let config = vm.config {
                nativeToolsOverview(config)
            } else if vm.isLoading {
                Section("扩展") {
                    CardLoadingView(minHeight: 100)
                }
            } else if let error = vm.error {
                Section("扩展") {
                    CardErrorView(error: error, minHeight: 80)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "扩展") {
                    Text("工具配置与扩展能力")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
    }

    @ViewBuilder
    private func nativeToolsOverview(_ config: ToolsConfig) -> some View {
        Section("工具配置") {
            if !config.allow.isEmpty {
                HomeDetailRow(title: "允许", value: config.allow.joined(separator: ", "))
            }
            if !config.deny.isEmpty {
                HomeDetailRow(title: "拒绝", value: config.deny.joined(separator: ", "))
            }
        }

        ForEach(config.groups) { group in
            Section(group.name) {
                ForEach(group.tools) { tool in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(tool.name)
                            .font(AppTypography.captionMono)
                        if !tool.description.isEmpty {
                            Text(tool.description)
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
            }
        }
    }
}
