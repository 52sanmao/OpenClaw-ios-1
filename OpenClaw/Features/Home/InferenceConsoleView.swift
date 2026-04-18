import SwiftUI

struct InferenceConsoleView: View {
    let adminVM: AdminViewModel

    var body: some View {
        List {
            summarySection

            if let config = adminVM.modelsConfig {
                ModelsSection(config: config, agents: adminVM.agents)
            } else if adminVM.isLoading {
                Section("推理") {
                    CardLoadingView(minHeight: 120)
                }
            } else if let error = adminVM.error {
                Section("推理") {
                    CardErrorView(error: error, minHeight: 80)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "模型") {
                    Text(subtitle)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
    }

    private var summarySection: some View {
        Section("推理概览") {
            HomeDetailRow(title: "主模型", value: adminVM.modelsConfig?.defaultModelDisplay ?? "未配置")
            HomeDetailRow(title: "回退模型", value: adminVM.modelsConfig?.fallbackModelDisplay ?? "未配置")
            HomeDetailRow(title: "代理数量", value: "\(adminVM.agents.count)")
        }
    }

    private var subtitle: String {
        adminVM.modelsConfig?.defaultModelDisplay ?? "查看当前推理配置"
    }
}
