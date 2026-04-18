import SwiftUI

struct HomeView: View {
    private static let cardReorderStep: CGFloat = 148

    @State private var systemVM: SystemHealthViewModel
    @State private var outreachVM: OutreachStatsViewModel
    @State private var blogVM: BlogPipelineViewModel
    @State private var commandsVM: CommandsViewModel
    @State private var tokenUsageVM: TokenUsageViewModel
    @State private var showAccountSwitcher = false
    @State private var cardOrder = HomeCardOrderStore.load()
    @State private var draggingCard: HomeCardID?
    @State private var isDraggingActive = false
    @State private var draggingOffset: CGFloat = 0
    @State private var lastReorderStep = 0

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
                            .simultaneousGesture(cardDragGesture(for: card.id))
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
            NavigationLink {
                SystemHealthDetailView(vm: systemVM)
            } label: {
                SystemHealthCard(vm: systemVM)
            }
            .buttonStyle(.plain)
        case .connectionDiagnostics:
            connectionDiagnosticsCard
        case .settingsModules:
            settingsModulesCard
        case .commands:
            CommandsCard(vm: commandsVM, client: client)
        case .cronSummary:
            NavigationLink {
                CronsTab(vm: cronVM, detailRepository: cronDetailRepository, client: client)
            } label: {
                CronSummaryCard(vm: cronVM)
            }
            .buttonStyle(.plain)
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

    private func cardDragGesture(for id: HomeCardID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 10, coordinateSpace: .local))
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if draggingCard != id {
                        draggingCard = id
                        draggingOffset = 0
                        lastReorderStep = 0
                        isDraggingActive = true
                        Haptics.shared.refreshComplete()
                    }
                    let translation = drag.translation.height
                    draggingOffset = translation * 0.55
                    reorderCard(id, translation: translation)
                default:
                    break
                }
            }
            .onEnded { _ in
                guard draggingCard == id else {
                    isDraggingActive = false
                    lastReorderStep = 0
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
                    }

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: systemVM.error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(systemVM.error == nil ? AppColors.success : AppColors.warning)
                        Text(systemVM.error == nil ? "聊天主链路看起来可用" : "统计扩展存在异常，建议打开诊断页检查")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.neutral)
                    }

                    HomeCardDetailHint()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var settingsModulesCard: some View {
        NavigationLink {
            CommandsDetailView(commandsVM: commandsVM, client: client)
        } label: {
            CardContainer(
                title: "控制中心",
                systemImage: "square.grid.2x2.fill",
                isStale: false,
                isLoading: false
            ) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("更直观地进入模型、渠道、技能和扩展")
                                .font(AppTypography.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("把控制台入口改成首页模块面板，直接看到重点区域和下一步去向。")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                        }
                        Spacer(minLength: Spacing.sm)
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text("8 个模块")
                                .font(AppTypography.captionBold)
                                .foregroundStyle(AppColors.primaryAction)
                            Text("可视化总览")
                                .font(AppTypography.nano)
                                .foregroundStyle(AppColors.neutral)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            Capsule()
                                .fill(AppColors.primaryAction.opacity(0.08))
                        )
                    }

                    LazyVGrid(columns: moduleGridColumns, spacing: Spacing.sm) {
                        moduleTile(
                            title: "模型",
                            subtitle: "默认与回退",
                            icon: "cpu.fill",
                            tint: AppColors.metricPrimary,
                            detail: commandsVM.isRunning.isEmpty ? "默认" : "执行中"
                        )
                        moduleTile(
                            title: "助手",
                            subtitle: "代理编排",
                            icon: "person.2.fill",
                            tint: AppColors.metricTertiary,
                            detail: "代理面板"
                        )
                        moduleTile(
                            title: "频道",
                            subtitle: "连接状态",
                            icon: "bubble.left.and.bubble.right.fill",
                            tint: AppColors.success,
                            detail: "渠道总览"
                        )
                        moduleTile(
                            title: "网络",
                            subtitle: "连接诊断",
                            icon: "network",
                            tint: AppColors.info,
                            detail: "连通性"
                        )
                        moduleTile(
                            title: "扩展",
                            subtitle: "工具配置",
                            icon: "slider.horizontal.3",
                            tint: AppColors.metricWarm,
                            detail: "原生工具"
                        )
                        moduleTile(
                            title: "MCP 服务",
                            subtitle: "服务器与工具",
                            icon: "server.rack",
                            tint: AppColors.metricSecondary,
                            detail: "MCP"
                        )
                        moduleTile(
                            title: "技能库",
                            subtitle: "技能文件",
                            icon: "bolt.circle.fill",
                            tint: AppColors.metricHighlight,
                            detail: "技能树"
                        )
                        moduleTile(
                            title: "用户管理",
                            subtitle: "账号与调试",
                            icon: "person.crop.circle.fill",
                            tint: AppColors.neutral,
                            detail: "设置"
                        )
                    }

                    HStack(spacing: Spacing.sm) {
                        quickEntryPill(title: "命令与管理", icon: "slider.horizontal.3")
                        quickEntryPill(title: "工具与 MCP", icon: "wrench.and.screwdriver")
                        quickEntryPill(title: "设置", icon: "gear")
                    }

                    HomeCardDetailHint()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var moduleGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: Spacing.sm),
            GridItem(.flexible(), spacing: Spacing.sm)
        ]
    }

    private func moduleTile(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .fill(AppColors.tintedBackground(tint, opacity: 0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(AppTypography.caption)
                        .foregroundStyle(tint)
                }
                Spacer(minLength: Spacing.xs)
                Text(detail)
                    .font(AppTypography.nano)
                    .foregroundStyle(tint)
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppColors.tintedBackground(tint, opacity: 0.12))
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.captionBold)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
                    .lineLimit(2)
            }

            HStack(spacing: Spacing.xxs) {
                Text("进入")
                    .font(AppTypography.nano)
                Image(systemName: "arrow.up.right")
                    .font(AppTypography.nano)
            }
            .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .strokeBorder(AppColors.tintedBackground(tint, opacity: 0.2), lineWidth: 1)
        )
    }

    private func quickEntryPill(title: String, icon: String) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(AppTypography.nano)
            Text(title)
                .font(AppTypography.nano)
                .lineLimit(1)
        }
        .foregroundStyle(AppColors.neutral)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule()
                .fill(AppColors.neutral.opacity(0.08))
        )
    }
}

private struct HomeCardDescriptor: Identifiable {
    let id: HomeCardID
}

private enum HomeCardID: String, CaseIterable, Codable {
    case systemHealth
    case connectionDiagnostics
    case settingsModules
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
        [.systemHealth, .connectionDiagnostics, .settingsModules, .commands, .cronSummary, .tokenUsage, .outreach, .blogPipeline]
    }
}
