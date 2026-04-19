import SwiftUI

struct HomeView: View {
    private static let cardReorderStep: CGFloat = 148

    @State private var systemVM: SystemHealthViewModel
    @State private var outreachVM: OutreachStatsViewModel
    @State private var blogVM: BlogPipelineViewModel
    @State private var commandsVM: CommandsViewModel
    @State private var tokenUsageVM: TokenUsageViewModel
    @State private var homeToolsVM: ToolsConfigViewModel
    @State private var homeAdminVM: AdminViewModel
    @State private var showAccountSwitcher = false
    @State private var cardOrder = HomeCardOrderStore.load()
    @State private var draggingCard: HomeCardID?
    @State private var armedDragCard: HomeCardID?
    @State private var isDraggingActive = false
    @State private var draggingOffset: CGFloat = 0
    @State private var lastReorderStep = 0

    @Bindable private var accountStore: AccountStore
    private let cronVM: CronSummaryViewModel
    private let client: GatewayClientProtocol
    private let cronDetailRepository: CronDetailRepository
    private let memoryVM: MemoryViewModel

    init(accountStore: AccountStore, client: GatewayClientProtocol, cronVM: CronSummaryViewModel, cronDetailRepository: CronDetailRepository, memoryVM: MemoryViewModel) {
        self.accountStore = accountStore
        self.client = client
        self.cronVM = cronVM
        self.cronDetailRepository = cronDetailRepository
        self.memoryVM = memoryVM
        _systemVM     = State(initialValue: SystemHealthViewModel(repository: RemoteSystemHealthRepository(client: client)))
        _outreachVM   = State(initialValue: OutreachStatsViewModel(repository: RemoteOutreachRepository(client: client)))
        _blogVM       = State(initialValue: BlogPipelineViewModel(repository: RemoteBlogRepository(client: client)))
        _commandsVM   = State(initialValue: CommandsViewModel(client: client, cronRepository: RemoteCronRepository(client: client), cronDetailRepository: cronDetailRepository))
        _tokenUsageVM = State(initialValue: TokenUsageViewModel(client: client))
        _homeToolsVM = State(initialValue: ToolsConfigViewModel(client: client))
        _homeAdminVM = State(initialValue: AdminViewModel(client: client))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    ForEach(orderedCards) { card in
                        homeCardView(card.id)
                            .overlay(alignment: .topTrailing) {
                                if isDraggingActive && draggingCard == card.id {
                                    Image(systemName: "line.3.horizontal")
                                        .font(AppTypography.micro)
                                        .foregroundStyle(AppColors.primaryAction)
                                        .padding(Spacing.xs)
                                        .transition(.opacity)
                                }
                            }
                            .scaleEffect(draggingCard == card.id && isDraggingActive ? 1.01 : 1.0)
                            .offset(y: draggingCard == card.id && isDraggingActive ? draggingOffset : 0)
                            .shadow(
                                color: draggingCard == card.id && isDraggingActive ? .black.opacity(0.08) : .clear,
                                radius: draggingCard == card.id && isDraggingActive ? 8 : 0,
                                x: 0,
                                y: draggingCard == card.id && isDraggingActive ? 4 : 0
                            )
                            .zIndex(draggingCard == card.id ? 1 : 0)
                            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.84), value: draggingCard)
                            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.84), value: draggingOffset)
                            .highPriorityGesture(cardDragGesture(for: card.id), including: armedDragCard == card.id ? .gesture : .subviews)
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
                    DetailTitleView(title: "控制台") {
                        homeSubtitle
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: Spacing.sm) {
                        NavigationLink {
                            ChatTab(
                                client: client,
                                memoryVM: memoryVM,
                                cronVM: cronVM,
                                cronDetailRepository: cronDetailRepository,
                                accountStore: accountStore
                            )
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
                            SettingsConsoleView(accountStore: accountStore, client: client, memoryVM: memoryVM, initialSection: .network)
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
        }
        .onAppear {
            systemVM.startPolling()
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
            if homeAdminVM.modelsConfig == nil && !homeAdminVM.isLoading {
                await homeAdminVM.load()
            }
            if homeToolsVM.config == nil && !homeToolsVM.isLoading {
                await homeToolsVM.load()
            }
            if memoryVM.skills.isEmpty && !memoryVM.isLoadingSkills {
                await memoryVM.loadSkills()
            }
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
            NavigationLink {
                SystemHealthDetailView(vm: systemVM)
            } label: {
                SystemHealthCard(vm: systemVM)
            }
            .buttonStyle(.plain)
        case .settingsModules:
            settingsModulesCard
        case .commands:
            CommandsCard(vm: commandsVM, client: client)
        case .tokenUsage:
            TokenUsageCard(vm: tokenUsageVM, detailRepository: cronDetailRepository)
        case .outreach:
            if outreachVM.data != nil {
                NavigationLink {
                    OutreachDetailView(vm: outreachVM)
                } label: {
                    OutreachStatsCard(vm: outreachVM)
                }
                .buttonStyle(.plain)
            }
        case .blogPipeline:
            if blogVM.data != nil {
                NavigationLink {
                    BlogPipelineDetailView(vm: blogVM)
                } label: {
                    BlogPipelineCard(vm: blogVM)
                }
                .buttonStyle(.plain)
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
        let step = Int((translation / Self.cardReorderStep).rounded())
        guard step != lastReorderStep else { return }

        let targetIndex = min(
            max(sourceIndex + (step - lastReorderStep), 0),
            cardOrder.count - 1
        )
        guard targetIndex != sourceIndex else {
            lastReorderStep = step
            return
        }

        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.86)) {
            let moved = cardOrder.remove(at: sourceIndex)
            cardOrder.insert(moved, at: targetIndex)
        }
        lastReorderStep = step
    }

    private func beginDragging(_ id: HomeCardID) {
        armedDragCard = id
        draggingCard = id
        draggingOffset = 0
        lastReorderStep = 0
        isDraggingActive = true
        Haptics.shared.refreshComplete()
    }

    private func cardDragGesture(for id: HomeCardID) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard armedDragCard == id else { return }
                if draggingCard != id || !isDraggingActive {
                    beginDragging(id)
                }
                let translation = value.translation.height
                draggingOffset = translation * 0.55
                reorderCard(id, translation: translation)
            }
            .onEnded { _ in
                guard armedDragCard == id else { return }
                armedDragCard = nil
                guard draggingCard == id else {
                    isDraggingActive = false
                    lastReorderStep = 0
                    draggingOffset = 0
                    return
                }
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                    draggingCard = nil
                    draggingOffset = 0
                    isDraggingActive = false
                }
                lastReorderStep = 0
                HomeCardOrderStore.save(cardOrder)
                Haptics.shared.success()
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

    private var settingsModulesCard: some View {
        ControlCenterView(
            sections: controlCenterSections,
            isDragging: armedDragCard == .settingsModules || draggingCard == .settingsModules,
            onDragHandlePress: {
                armedDragCard = .settingsModules
            }
        )
    }

    private var controlCenterSections: [ControlCenterSection] {
        [
            ControlCenterSection(
                id: "intelligence",
                title: "智能",
                subtitle: "推理 · 代理",
                icon: "cpu.fill",
                tint: AppColors.metricPrimary,
                modules: [
                    ControlCenterModule(
                        id: "models",
                        title: "推理",
                        subtitle: "模型与提供商",
                        icon: "cpu.fill",
                        tint: AppColors.metricPrimary,
                        detail: homeAdminVM.selectedModel ?? homeAdminVM.modelsConfig?.defaultModelDisplay ?? "模型",
                        destination: AnyView(InferenceConsoleView(adminVM: homeAdminVM))
                    ),
                    ControlCenterModule(
                        id: "agents",
                        title: "代理",
                        subtitle: "身份与行为",
                        icon: "person.2.fill",
                        tint: AppColors.metricTertiary,
                        detail: homeAdminVM.agent?.displayName ?? "代理",
                        destination: AnyView(AgentsConsoleView(adminVM: homeAdminVM))
                    )
                ]
            ),
            ControlCenterSection(
                id: "automation",
                title: "自动化",
                subtitle: "定时任务 · 技能",
                icon: "clock.arrow.2.circlepath",
                tint: AppColors.metricSecondary,
                modules: [
                    ControlCenterModule(
                        id: "crons",
                        title: "定时任务",
                        subtitle: "任务与历史",
                        icon: "clock.arrow.2.circlepath",
                        tint: AppColors.metricSecondary,
                        detail: cronModuleDetail,
                        destination: AnyView(CronsTab(vm: cronVM, detailRepository: cronDetailRepository, client: client))
                    ),
                    ControlCenterModule(
                        id: "skills",
                        title: "技能库",
                        subtitle: "技能文件",
                        icon: "bolt.circle.fill",
                        tint: AppColors.info,
                        detail: memoryVM.skills.isEmpty ? "技能树" : "\(memoryVM.skills.count) 个技能",
                        destination: AnyView(SkillsListView(vm: memoryVM))
                    )
                ]
            ),
            ControlCenterSection(
                id: "connectivity",
                title: "连接",
                subtitle: "频道 · MCP",
                icon: "antenna.radiowaves.left.and.right",
                tint: AppColors.success,
                modules: [
                    ControlCenterModule(
                        id: "channels",
                        title: "频道",
                        subtitle: "连接状态",
                        icon: "bubble.left.and.bubble.right.fill",
                        tint: AppColors.success,
                        detail: "\((homeAdminVM.channelsStatus?.channels.filter { $0.isConnected }.count) ?? 0) 已连接",
                        destination: AnyView(ChannelsConsoleView(adminVM: homeAdminVM))
                    ),
                    ControlCenterModule(
                        id: "mcp",
                        title: "MCP 服务",
                        subtitle: "服务器与工具",
                        icon: "server.rack",
                        tint: AppColors.metricHighlight,
                        detail: "\(homeToolsVM.mcpServers.count) 个服务器",
                        destination: AnyView(McpServersView(vm: homeToolsVM))
                    )
                ]
            ),
            ControlCenterSection(
                id: "admin",
                title: "运维",
                subtitle: "扩展 · 用户",
                icon: "slider.horizontal.below.square",
                tint: AppColors.metricWarm,
                modules: [
                    ControlCenterModule(
                        id: "extensions",
                        title: "扩展",
                        subtitle: "工具配置",
                        icon: "puzzlepiece.extension.fill",
                        tint: AppColors.metricWarm,
                        detail: homeToolsVM.config?.profile.capitalized ?? "工具",
                        destination: AnyView(ExtensionsConsoleView(vm: homeToolsVM, adminVM: homeAdminVM))
                    ),
                    ControlCenterModule(
                        id: "users",
                        title: "用户管理",
                        subtitle: "账号与调试",
                        icon: "person.crop.circle.fill",
                        tint: AppColors.neutral,
                        detail: "\(accountStore.accounts.count) 个账号",
                        destination: AnyView(UsersConsoleView(accountStore: accountStore, client: client, adminVM: homeAdminVM))
                    )
                ]
            )
        ]
    }

    private var cronModuleDetail: String {
        let cronJobs = cronVM.data ?? []
        let failed = cronJobs.filter { $0.status == .failed }.count
        if failed > 0 {
            return "\(failed) 个失败"
        }
        if !cronJobs.isEmpty {
            return "\(cronJobs.count) 个任务"
        }
        return "定时计划"
    }
}

private struct HomeCardDescriptor: Identifiable {
    let id: HomeCardID
}

private enum HomeCardID: String, CaseIterable, Codable {
    case systemHealth
    case settingsModules
    case commands
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
        [.systemHealth, .settingsModules, .commands, .tokenUsage, .outreach, .blogPipeline]
    }
}
