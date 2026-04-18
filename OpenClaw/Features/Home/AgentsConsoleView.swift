import SwiftUI

struct AgentsConsoleView: View {
    let adminVM: AdminViewModel

    var body: some View {
        List {
            Section("代理概览") {
                HomeDetailRow(title: "代理总数", value: "\(adminVM.agents.count)")
                HomeDetailRow(title: "默认代理", value: defaultAgentName)
            }

            Section("代理列表") {
                if adminVM.isLoading && adminVM.agents.isEmpty {
                    CardLoadingView(minHeight: 100)
                } else if adminVM.agents.isEmpty {
                    Text("当前没有代理信息")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                } else {
                    ForEach(adminVM.agents) { agent in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack(spacing: Spacing.xs) {
                                Text(agent.emoji)
                                Text(agent.name)
                                    .font(AppTypography.body)
                                if agent.isDefault {
                                    Text("默认")
                                        .font(AppTypography.nano)
                                        .padding(.horizontal, Spacing.xxs)
                                        .padding(.vertical, 2)
                                        .background(AppColors.success.opacity(0.15), in: Capsule())
                                        .foregroundStyle(AppColors.success)
                                }
                            }
                            Text(agent.model ?? "未配置模型")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "助手") {
                    Text("代理编排与模型归属")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
    }

    private var defaultAgentName: String {
        adminVM.agents.first(where: { $0.isDefault })?.name ?? "未设置"
    }
}
