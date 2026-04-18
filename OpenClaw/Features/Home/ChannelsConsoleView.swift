import SwiftUI

struct ChannelsConsoleView: View {
    let adminVM: AdminViewModel

    var body: some View {
        List {
            Section("频道概览") {
                HomeDetailRow(title: "已连接频道", value: "\(connectedCount)")
                HomeDetailRow(title: "提供商窗口", value: "\(providerWindowCount)")
            }

            if let channels = adminVM.channelsStatus {
                ChannelsSection(status: channels)
            } else if adminVM.isLoading {
                Section("频道") {
                    CardLoadingView(minHeight: 100)
                }
            } else if let error = adminVM.error {
                Section("频道") {
                    CardErrorView(error: error, minHeight: 80)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "频道") {
                    Text("查看连接状态与配额窗口")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
    }

    private var connectedCount: Int {
        adminVM.channelsStatus?.channels.filter { $0.isConnected }.count ?? 0
    }

    private var providerWindowCount: Int {
        adminVM.channelsStatus?.providers.reduce(0) { $0 + $1.windows.count } ?? 0
    }
}
