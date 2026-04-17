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
                    connectionDiagnosticsCard
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
                            "聊天与定时任务仍可用",
                            systemImage: "message.badge",
                            description: Text("当前首页缺少的是 /stats/* 或 /tools/invoke 扩展数据，不是聊天主链路故障。你仍然可以继续使用聊天、线程历史和定时任务。")
                        )
                        .padding(.top, Spacing.sm)
                    }

                    if let systemError = systemVM.error {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("首页扩展接口失败")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.warning)
                            Text(systemError.localizedDescription)
                                .font(AppTypography.captionMono)
                                .foregroundStyle(AppColors.neutral)
                            Text("如果右下角日志里仍能看到 /v1/models、/api/chat/thread/new、/api/chat/send、/api/chat/history 成功，这说明失败点在统计扩展接口，而不是聊天主链路。")
                                .font(AppTypography.nano)
                                .foregroundStyle(AppColors.neutral)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("首页卡片为空通常表示扩展统计接口未启用；这不会阻止 IronClaw 的聊天、线程历史或定时任务主路径。")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("若要定位失败阶段，请打开右下角日志浮窗；日志会记录模型探活、建线程、发送消息、历史轮询与 routines 请求。")
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var connectionDiagnosticsCard: some View {
        NavigationLink {
            ToolsConfigView(client: client)
        } label: {
            CardContainer(
                title: "连接诊断",
                systemImage: "heart.text.square",
                isStale: false,
                isLoading: false
            ) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("健康与频道")
                                .font(AppTypography.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("参考云桥连接区下方的诊断入口，用来查看工具、MCP 服务器与扩展能力状态。")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: systemVM.error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(systemVM.error == nil ? AppColors.success : AppColors.warning)
                        Text(systemVM.error == nil ? "聊天主链路看起来可用" : "统计扩展存在异常，建议打开诊断查看详情")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
