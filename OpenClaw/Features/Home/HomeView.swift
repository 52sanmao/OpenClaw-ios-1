import SwiftUI

struct HomeView: View {
    @State private var systemVM: SystemHealthViewModel
    @State private var outreachVM: OutreachStatsViewModel
    @State private var blogVM: BlogPipelineViewModel
    @State private var commandsVM: CommandsViewModel
    @State private var tokenUsageVM: TokenUsageViewModel
    @State private var showAccountSwitcher = false

    @Bindable private var accountStore: AccountStore
    private let cronVM: CronSummaryViewModel
    private let client: GatewayClientProtocol
    private let cronDetailRepository: CronDetailRepository

    init(accountStore: AccountStore, client: GatewayClientProtocol, cronVM: CronSummaryViewModel, cronDetailRepository: CronDetailRepository) {
        self.accountStore = accountStore
        self.client = client
        self.cronVM = cronVM
        self.cronDetailRepository = cronDetailRepository
        _systemVM     = State(initialValue: SystemHealthViewModel(repository: RemoteSystemHealthRepository(client: client)))
        _outreachVM   = State(initialValue: OutreachStatsViewModel(repository: RemoteOutreachRepository(client: client)))
        _blogVM       = State(initialValue: BlogPipelineViewModel(repository: RemoteBlogRepository(client: client)))
        _commandsVM   = State(initialValue: CommandsViewModel(client: client, cronRepository: RemoteCronRepository(client: client), cronDetailRepository: cronDetailRepository))
        _tokenUsageVM = State(initialValue: TokenUsageViewModel(client: client))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    SystemHealthCard(vm: systemVM)
                    CommandsCard(vm: commandsVM, client: client)
                    CronSummaryCard(vm: cronVM)

                    TokenUsageCard(vm: tokenUsageVM, detailRepository: cronDetailRepository)

                    // Optional cards — only show if data loaded successfully
                    if outreachVM.data != nil {
                        OutreachStatsCard(vm: outreachVM)
                    }
                    if blogVM.data != nil {
                        BlogPipelineCard(vm: blogVM)
                    }

                    if systemVM.data == nil && tokenUsageVM.data == nil {
                        ContentUnavailableView(
                            "当前部署以聊天能力为主",
                            systemImage: "server.rack",
                            description: Text("该 IronClaw 服务器已提供聊天、线程历史、模型发现与网关状态，但未启用 /stats/* 与 /tools/invoke 扩展接口。")
                        )
                        .padding(.top, Spacing.sm)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .refreshable {
                async let s: Void = systemVM.refresh()
                async let c: Void = cronVM.refresh()
                async let o: Void = outreachVM.refresh()
                async let b: Void = blogVM.refresh()
                async let t: Void = tokenUsageVM.refresh()
                _ = await (s, c, o, b, t)
                Haptics.shared.refreshComplete()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    DetailTitleView(title: accountStore.activeAccount?.name ?? "首页") {
                        homeSubtitle
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: Spacing.sm) {
                        NavigationLink {
                            ChatTab(client: client)
                        } label: {
                            Image("openclaw")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                        if accountStore.accounts.count > 1 {
                            Button {
                                showAccountSwitcher = true
                            } label: {
                                Image(systemName: "server.rack")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: Spacing.sm) {
                        NavigationLink {
                            ToolsConfigView(client: client)
                        } label: {
                            Image(systemName: "wrench.and.screwdriver")
                        }
                        NavigationLink {
                            SettingsView(accountStore: accountStore, client: client)
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
            }
        }
        .onAppear {
            systemVM.startPolling()
        }
        .onDisappear {
            systemVM.stopPolling()
        }
        .task {
            cronVM.start()
            outreachVM.start()
            blogVM.start()
            tokenUsageVM.start()
        }
        .confirmationDialog("Switch Account", isPresented: $showAccountSwitcher, titleVisibility: .visible) {
            ForEach(accountStore.accounts) { account in
                Button(account.name + (account.id == accountStore.activeAccountId ? " ✓" : "")) {
                    guard account.id != accountStore.activeAccountId else { return }
                    accountStore.setActive(account.id)
                }
            }
        }
    }

    @ViewBuilder
    private var homeSubtitle: some View {
        let cronJobs = cronVM.data ?? []
        let failedCrons = cronJobs.filter { $0.status == .failed }.count
        let systemOk = systemVM.data != nil && systemVM.error == nil

        if failedCrons > 0 {
            Text("\(failedCrons) 个定时任务失败")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.danger)
        } else if !systemOk && systemVM.error != nil {
            Text("系统暂不可用")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.warning)
        } else if cronJobs.isEmpty {
            Text("加载中…")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.neutral)
        } else {
            Text("系统运行正常")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.success)
        }
    }
}
