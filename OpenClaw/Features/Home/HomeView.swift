import SwiftUI

struct HomeView: View {
    @State private var systemVM: SystemHealthViewModel
    @State private var outreachVM: OutreachStatsViewModel
    @State private var blogVM: BlogPipelineViewModel
    @State private var commandsVM: CommandsViewModel
    @State private var tokenUsageVM: TokenUsageViewModel
    @State private var showAccountSwitcher = false
    @State private var taskToggleEnabled = true
    @State private var cardOrder = HomeCardOrderStore.load()
    @State private var draggingCard: HomeCardID?

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
                    ForEach(orderedCards) { card in
                        homeCardView(card.id)
                            .overlay(alignment: .topTrailing) {
                                if draggingCard == card.id {
                                    Image(systemName: "line.3.horizontal")
                                        .font(AppTypography.micro)
                                        .foregroundStyle(AppColors.primaryAction)
                                        .padding(Spacing.xs)
                                }
                            }
                            .scaleEffect(draggingCard == card.id ? 1.01 : 1.0)
                            .opacity(draggingCard == card.id ? 0.92 : 1.0)
                            .animation(.easeInOut(duration: 0.18), value: draggingCard)
                            .onLongPressGesture(minimumDuration: 0.35) {
                                draggingCard = card.id
                            }
                            .gesture(
                                DragGesture(minimumDistance: 12)
                                    .onChanged { value in
                                        guard draggingCard == card.id else { return }
                                        reorderCard(card.id, translation: value.translation.height)
                                    }
                                    .onEnded { _ in
                                        guard draggingCard == card.id else { return }
                                        draggingCard = nil
                                        HomeCardOrderStore.save(cardOrder)
                                    }
                            )
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
                taskToggleEnabled = (cronVM.data ?? []).contains { $0.enabled }
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
            taskToggleEnabled = (cronVM.data ?? []).contains { $0.enabled }
            cardOrder = HomeCardOrderStore.load()
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
        .confirmationDialog("切换账号", isPresented: $showAccountSwitcher, titleVisibility: .visible) {
            ForEach(accountStore.accounts) { account in
                Button(account.name + (account.id == accountStore.activeAccountId ? " ✓" : "")) {
                    guard account.id != accountStore.activeAccountId else { return }
                    accountStore.setActive(account.id)
                }
            }
        }
    }

    private var orderedCards: [HomeCardDescriptor] {
        cardOrder.compactMap { id in
            guard isCardAvailable(id) else { return nil }
            return HomeCardDescriptor(id: id)
        }
    }

    @ViewBuilder
    private func homeCardView(_ id: HomeCardID) -> some View {
        switch id {
        case .systemHealth:
            SystemHealthCard(vm: systemVM)
        case .connectionDiagnostics:
            connectionDiagnosticsCard
        case .settingsModules:
            settingsModulesCard
        case .taskToggle:
            taskToggleCard
        case .commands:
            CommandsCard(vm: commandsVM, client: client)
        case .cronSummary:
            CronSummaryCard(vm: cronVM)
        case .tokenUsage:
            TokenUsageCard(vm: tokenUsageVM, detailRepository: cronDetailRepository)
        case .outreach:
            if outreachVM.data != nil {
                OutreachStatsCard(vm: outreachVM)
            }
        case .blogPipeline:
            if blogVM.data != nil {
                BlogPipelineCard(vm: blogVM)
            }
        }
    }

    private func isCardAvailable(_ id: HomeCardID) -> Bool {
        switch id {
        case .outreach:
            return outreachVM.data != nil
        case .blogPipeline:
            return blogVM.data != nil
        default:
            return true
        }
    }

    private func reorderCard(_ id: HomeCardID, translation: CGFloat) {
        guard let sourceIndex = cardOrder.firstIndex(of: id) else { return }
        let threshold: CGFloat = 70
        var targetIndex = sourceIndex
        if translation > threshold {
            targetIndex = min(sourceIndex + 1, cardOrder.count - 1)
        } else if translation < -threshold {
            targetIndex = max(sourceIndex - 1, 0)
        }
        guard targetIndex != sourceIndex else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            let moved = cardOrder.remove(at: sourceIndex)
            cardOrder.insert(moved, at: targetIndex)
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

    private var settingsModulesCard: some View {
        NavigationLink {
            SettingsView(accountStore: accountStore, client: client)
        } label: {
            CardContainer(
                title: "设置分组",
                systemImage: "square.grid.2x2",
                isStale: false,
                isLoading: false
            ) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("模型、助手、频道、网络、扩展、MCP 服务、技能库、用户管理")
                        .font(AppTypography.caption)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xs) {
                        modulePill("模型", icon: "cpu")
                        modulePill("助手", icon: "sparkles")
                        modulePill("频道", icon: "bubble.left.and.bubble.right")
                        modulePill("网络", icon: "network")
                        modulePill("扩展", icon: "puzzlepiece.extension")
                        modulePill("MCP 服务", icon: "server.rack")
                        modulePill("技能库", icon: "square.stack.3d.up")
                        modulePill("用户管理", icon: "person.2")
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var taskToggleCard: some View {
        CardContainer(
            title: "任务",
            systemImage: "clock.fill",
            isStale: false,
            isLoading: false
        ) {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("任务开关")
                        .font(AppTypography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(taskToggleEnabled ? "当前至少有一个任务已启用" : "当前所有任务都已关闭")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }

                Spacer()

                Toggle("", isOn: $taskToggleEnabled)
                    .labelsHidden()
                    .scaleEffect(0.75)
                    .tint(AppColors.primaryAction)
                    .onChange(of: taskToggleEnabled) { _, newValue in
                        Task { await setAllTasksEnabled(newValue) }
                    }
            }
        }
    }

    @ViewBuilder
    private func modulePill(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(AppTypography.micro)
            Text(title)
                .font(AppTypography.micro)
                .lineLimit(1)
        }
        .foregroundStyle(AppColors.primaryAction)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.primaryAction.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    private func setAllTasksEnabled(_ enabled: Bool) async {
        guard let jobs = cronVM.data, !jobs.isEmpty else { return }
        for job in jobs where job.enabled != enabled {
            do {
                try await cronDetailRepository.setEnabled(jobId: job.id, enabled: enabled)
            } catch {
                taskToggleEnabled = !enabled
                Haptics.shared.error()
                return
            }
        }
        await cronVM.refresh()
        taskToggleEnabled = (cronVM.data ?? []).contains { $0.enabled }
        Haptics.shared.success()
    }
}

private struct HomeCardDescriptor: Identifiable {
    let id: HomeCardID
}

private enum HomeCardID: String, CaseIterable, Codable {
    case systemHealth
    case connectionDiagnostics
    case settingsModules
    case taskToggle
    case commands
    case cronSummary
    case tokenUsage
    case outreach
    case blogPipeline
}

private enum HomeCardOrderStore {
    private static let key = "openclaw.home.cardOrder"

    static func load() -> [HomeCardID] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode([HomeCardID].self, from: data) else {
            return defaultOrder
        }
        let filtered = stored.filter { defaultOrder.contains($0) }
        let missing = defaultOrder.filter { !filtered.contains($0) }
        return filtered + missing
    }

    static func save(_ order: [HomeCardID]) {
        guard let data = try? JSONEncoder().encode(order) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static var defaultOrder: [HomeCardID] {
        [.systemHealth, .connectionDiagnostics, .settingsModules, .taskToggle, .commands, .cronSummary, .tokenUsage, .outreach, .blogPipeline]
    }
}
