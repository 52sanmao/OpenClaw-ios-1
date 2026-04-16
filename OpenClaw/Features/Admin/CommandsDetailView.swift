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
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("命令与管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
