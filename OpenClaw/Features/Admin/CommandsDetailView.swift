import SwiftUI

struct CommandsDetailView: View {
    @State var commandsVM: CommandsViewModel
    @State private var adminVM: AdminViewModel
    @State private var commandToConfirm: QuickCommand?
    private let client: GatewayClientProtocol

    private let columns = QuickCommand.gridColumns

    init(commandsVM: CommandsViewModel, client: GatewayClientProtocol) {
        self.commandsVM = commandsVM
        self.client = client
        _adminVM = State(initialValue: AdminViewModel(client: client))
    }

    var body: some View {
        List {
            // All commands grid
            Section("命令") {
                LazyVGrid(columns: columns, spacing: Spacing.xs) {
                    ForEach(QuickCommand.all) { cmd in
                        CommandButton(
                            command: cmd,
                            isRunning: commandsVM.isCommandRunning(cmd.id)
                        ) {
                            commandToConfirm = cmd
                        }
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }

            // Admin sections
            if adminVM.isLoading && adminVM.modelsConfig == nil {
                Section("模型与配置") {
                    CardLoadingView(minHeight: 60)
                }
                Section("渠道") {
                    CardLoadingView(minHeight: 60)
                }
            } else {
                if let config = adminVM.modelsConfig {
                    ModelsSection(config: config, agents: adminVM.agents)
                }

                if let channels = adminVM.channelsStatus {
                    ChannelsSection(status: channels)
                }

                if let err = adminVM.error, adminVM.modelsConfig == nil {
                    Section {
                        VStack(spacing: Spacing.xs) {
                            CardErrorView(error: err, minHeight: 60)
                            Text(adminVM.unavailableDescription)
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                            Text("右下角日志会显示 models-status、agents-list、channels-list 的逐步请求结果，可直接判断失败发生在哪个 stats/exec 命令。")
                                .font(AppTypography.nano)
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
                DetailTitleView(title: "命令与管理") {
                    if adminVM.error != nil && adminVM.modelsConfig == nil {
                        Text("管理数据不可用")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.warning)
                    } else if let _ = adminVM.modelsConfig {
                        Text("默认模型 · \(adminVM.agents.count) 个代理 · \(adminVM.channelsStatus?.channels.filter(\\.isConnected).count ?? 0) 个已连接渠道")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    } else {
                        Text("加载管理与渠道信息")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    ToolsConfigView(client: client)
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
            }
        }
        .refreshable {
            await adminVM.load()
            Haptics.shared.refreshComplete()
        }
        .task { await adminVM.load() }
        .alert("运行命令？", isPresented: Binding(
            get: { commandToConfirm != nil },
            set: { if !$0 { commandToConfirm = nil } }
        )) {
            Button("运行", role: .destructive) {
                guard let cmd = commandToConfirm else { return }
                Task { await commandsVM.execute(cmd) }
            }
            Button("取消", role: .cancel) { commandToConfirm = nil }
        } message: {
            if let cmd = commandToConfirm {
                Text(cmd.confirmMessage)
            }
        }
        .sheet(item: $commandsVM.result) { result in
            CommandResultSheet(result: result, vm: commandsVM)
        }
    }
}
