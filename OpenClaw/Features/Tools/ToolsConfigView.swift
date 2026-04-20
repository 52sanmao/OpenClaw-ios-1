import SwiftUI

struct ToolsConfigView: View {
    @State private var vm: ToolsConfigViewModel
    private let client: GatewayClientProtocol

    init(client: GatewayClientProtocol) {
        self.client = client
        _vm = State(initialValue: ToolsConfigViewModel(client: client))
    }

    var body: some View {
        List {
            if vm.isLoading && vm.config == nil {
                CardLoadingView(minHeight: 100)
            } else if let config = vm.config {
                nativeToolsSection(config)
            } else if let err = vm.error {
                VStack(spacing: Spacing.xs) {
                    CardErrorView(error: err, minHeight: 60)
                    Text(vm.unavailableDescription)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                        .padding(.horizontal, Spacing.xs)
                    Text("右下角日志会显示 tools-list、mcp-list、mcp-tools 的请求结果，可直接看到失败发生在哪一个 stats/exec 命令。")
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                        .padding(.horizontal, Spacing.xs)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "工具权限") {
                    Text(vm.config.map { "\($0.groups.reduce(0) { $0 + $1.tools.count }) 个原生工具" } ?? "原生工具配置")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .refreshable {
            await vm.load()
            Haptics.shared.refreshComplete()
        }
        .task { await vm.load() }
    }

    @ViewBuilder
    private func nativeToolsSection(_ config: ToolsConfig) -> some View {
        Section {
            HStack {
                Text("配置档")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.neutral)
                Spacer()
                Text(config.profile.capitalized)
                    .font(AppTypography.captionBold)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(config.profileColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(config.profileColor)
            }

            if !config.allow.isEmpty {
                LabeledContent("允许") {
                    Text(config.allow.joined(separator: ", "))
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.success)
                }
            }
            if !config.deny.isEmpty {
                LabeledContent("拒绝") {
                    Text(config.deny.joined(separator: ", "))
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.danger)
                }
            }
        } header: {
            HStack {
                Text("原生工具")
                let count = config.groups.reduce(0) { $0 + $1.tools.count }
                Text("(\(count))")
                    .foregroundStyle(AppColors.neutral)
            }
        } footer: {
            Text("MCP 服务器与工具明细已独立到控制台的「MCP 服务」页面，这里只保留原生工具权限。")
        }

        ForEach(config.groups) { group in
            Section {
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
            } header: {
                Label(group.name, systemImage: group.icon)
            }
        }
    }
}

