import SwiftUI

struct SettingsConsoleView: View {
    let accountStore: AccountStore
    let client: GatewayClientProtocol
    let memoryVM: MemoryViewModel

    @State private var toolsVM: ToolsConfigViewModel
    @State private var adminVM: AdminViewModel
    @State private var commandsVM: CommandsViewModel
    @State private var selectedSection: SettingsConsoleSection
    @State private var debugEnabled: Bool = AppDebugSettings.debugEnabled
    @State private var logLevel: String?
    @State private var isLoadingLogLevel = false

    init(accountStore: AccountStore, client: GatewayClientProtocol, memoryVM: MemoryViewModel, initialSection: SettingsConsoleSection = .network) {
        self.accountStore = accountStore
        self.client = client
        self.memoryVM = memoryVM
        _toolsVM = State(initialValue: ToolsConfigViewModel(client: client))
        _adminVM = State(initialValue: AdminViewModel(client: client))
        _commandsVM = State(initialValue: CommandsViewModel(client: client, cronRepository: RemoteCronRepository(client: client), cronDetailRepository: RemoteCronDetailRepository(client: client)))
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        List {
            sectionPicker

            switch selectedSection {
            case .network:
                networkSection
            case .agent:
                agentSection
            case .commands:
                commandsSection
            case .users:
                usersSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "设置") {
                    Text(selectedSection.subtitle)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .task {
            if toolsVM.config == nil && !toolsVM.isLoading {
                await toolsVM.load()
            }
            if adminVM.agents.isEmpty && !adminVM.isLoading {
                await adminVM.load()
            }
            await loadLogLevel()
        }
        .refreshable {
            async let tools: Void = toolsVM.load()
            async let admin: Void = adminVM.load()
            async let level: Void = loadLogLevel()
            _ = await (tools, admin, level)
            Haptics.shared.refreshComplete()
        }
    }

    private func loadLogLevel() async {
        guard !isLoadingLogLevel else { return }
        isLoadingLogLevel = true
        defer { isLoadingLogLevel = false }
        do {
            let dto: LogLevelDTO = try await client.stats("api/logs/level")
            logLevel = dto.level
        } catch {
            AppLogStore.shared.append("SettingsConsoleView: /api/logs/level 失败 \(error.localizedDescription)")
        }
    }

    private var sectionPicker: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(SettingsConsoleSection.allCases) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: section.icon)
                                    .font(AppTypography.nano)
                                Text(section.title)
                                    .font(AppTypography.nano)
                            }
                            .foregroundStyle(selectedSection == section ? Color.white : AppColors.neutral)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                Capsule()
                                    .fill(selectedSection == section ? AppColors.primaryAction : AppColors.neutral.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
        } header: {
            Text("设置域")
        }
    }

    private var networkSection: some View {
        Group {
            Section("连接与诊断") {
                navigationSummaryRow(
                    title: "当前账号",
                    value: accountStore.activeAccount?.name ?? "未配置",
                    detail: accountStore.activeAccount?.displayURL ?? "请先添加网关账号",
                    icon: "network",
                    tint: AppColors.info
                )
            }

            Section {
                Toggle(isOn: $debugEnabled) {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: AppRadius.md)
                                .fill(AppColors.tintedBackground(debugEnabled ? AppColors.warning : AppColors.neutral, opacity: 0.14))
                                .frame(width: 38, height: 38)
                            Image(systemName: debugEnabled ? "ladybug.fill" : "ladybug")
                                .font(AppTypography.caption)
                                .foregroundStyle(debugEnabled ? AppColors.warning : AppColors.neutral)
                        }
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("调试模式")
                                .font(AppTypography.body)
                            Text(debugEnabled ? "日志浮窗、调试输出与诊断详情均已启用" : "当前只保留正常运行所需界面")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                .tint(AppColors.primaryAction)
                .onChange(of: debugEnabled) { _, newValue in
                    AppDebugSettings.debugEnabled = newValue
                    if !newValue {
                        AppLogStore.shared.clear()
                    }
                    Haptics.shared.refreshComplete()
                }
            } header: {
                Text("全局调试")
            } footer: {
                Text("控制所有调试界面的显隐：日志浮窗、诊断详情、扩展调试输出。关闭后立即清空已收集的日志，不影响聊天主链路。")
            }

            Section("网关日志级别") {
                HStack(spacing: Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .fill(AppColors.metricHighlight.opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: "text.line.last.and.arrowtriangle.forward")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.metricHighlight)
                    }
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("当前日志级别")
                            .font(AppTypography.body)
                        Text("GET /api/logs/level")
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                    Spacer()
                    if isLoadingLogLevel {
                        ProgressView().scaleEffect(0.75)
                    } else if let level = logLevel {
                        Text(level)
                            .font(AppTypography.captionBold)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(AppColors.metricHighlight.opacity(0.14)))
                            .foregroundStyle(AppColors.metricHighlight)
                    } else {
                        Text("—")
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }

            Section("诊断入口") {
                NavigationLink {
                    SettingsView(accountStore: accountStore, client: client)
                } label: {
                    settingsRow(
                        title: "连接与诊断",
                        subtitle: "测试连接、查看诊断详情与账号切换",
                        icon: "heart.text.square.fill",
                        tint: AppColors.info
                    )
                }

                NavigationLink {
                    ToolsConfigView(client: client)
                } label: {
                    settingsRow(
                        title: "工具配置",
                        subtitle: "查看原生工具、权限白名单与链路状态",
                        icon: "wrench.and.screwdriver.fill",
                        tint: AppColors.metricPrimary
                    )
                }
            }
        }
    }

    private var commandsSection: some View {
        Group {
            Section("命令中心") {
                navigationSummaryRow(
                    title: "快捷命令",
                    value: "\(QuickCommand.visibleCount) 个",
                    detail: "重启、体检、日志尾部、状态、安全、备份",
                    icon: "terminal.fill",
                    tint: AppColors.metricWarm
                )
                navigationSummaryRow(
                    title: "完整命令集",
                    value: "\(QuickCommand.all.count) 个",
                    detail: "包含定时任务暂停、渠道检查、索引重建等运维动作",
                    icon: "switch.2",
                    tint: AppColors.primaryAction
                )
            }

            Section {
                CommandsCard(vm: commandsVM)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section("深度管理") {
                NavigationLink {
                    CommandsDetailView(commandsVM: commandsVM, client: client)
                } label: {
                    settingsRow(
                        title: "命令与管理",
                        subtitle: "查看全部命令、模型配置与频道状态",
                        icon: "slider.horizontal.below.rectangle",
                        tint: AppColors.metricHighlight
                    )
                }
            }
        }
    }

    private var agentSection: some View {
        Group {
            Section("当前代理") {
                NavigationLink {
                    AgentSettingsView(adminVM: adminVM)
                } label: {
                    settingsRow(
                        title: adminVM.agent?.displayName ?? "代理管理",
                        subtitle: adminVM.agent.map { "\($0.role) · \($0.model)" } ?? "查看代理详情、行为与激活频道",
                        icon: "person.crop.circle.fill",
                        tint: AppColors.metricTertiary
                    )
                }
            }

            if let agent = adminVM.agent {
                Section("代理设置项") {
                    inlineSettingRow(
                        title: "使用规划",
                        subtitle: "agent.use_planning",
                        icon: "brain.head.profile",
                        tint: agent.usePlanning ? AppColors.success : AppColors.neutral,
                        value: agent.usePlanning ? "启用" : "禁用"
                    )
                    inlineSettingRow(
                        title: "自动批准工具",
                        subtitle: "agent.auto_approve_tools",
                        icon: "checkmark.circle.fill",
                        tint: agent.autoApproveTools ? AppColors.success : AppColors.neutral,
                        value: agent.autoApproveTools ? "启用" : "禁用"
                    )
                    inlineSettingRow(
                        title: "允许本地工具",
                        subtitle: "agent.allow_local_tools",
                        icon: "wrench.and.screwdriver",
                        tint: agent.allowLocalTools ? AppColors.success : AppColors.neutral,
                        value: agent.allowLocalTools ? "启用" : "禁用"
                    )
                } footer: {
                    Text("这三项就是当前网关已暴露到 iOS 端的代理核心设置。更完整的代理信息（激活频道、模型、角色）可进入详情页查看。")
                }
            }
        }
    }

    private var usersSection: some View {
        Group {
            Section("本地网关账户") {
                if let active = accountStore.activeAccount {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: AppRadius.md)
                                .fill(AppColors.success.opacity(0.14))
                                .frame(width: 38, height: 38)
                            Image(systemName: "checkmark.circle.fill")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.success)
                        }
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(active.name)
                                .font(AppTypography.body)
                            Text(active.displayURL)
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text("使用中")
                            .font(AppTypography.nano)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.success.opacity(0.15)))
                            .foregroundStyle(AppColors.success)
                    }
                    .padding(.vertical, Spacing.xxs)
                }

                NavigationLink {
                    SettingsView(accountStore: accountStore, client: client)
                } label: {
                    settingsRow(
                        title: "账号与调试",
                        subtitle: "\(accountStore.accounts.count) 个账号 · 切换 / 连接测试 / 诊断",
                        icon: "person.crop.circle.fill",
                        tint: AppColors.success
                    )
                }
            } footer: {
                Text("这里管理的是本机保存的网关连接账户，不是远程 IronClaw 的用户列表。")
            }
        }
    }

    private func settingsRow(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColors.tintedBackground(tint, opacity: 0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(AppTypography.caption)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(AppTypography.body)
                Text(subtitle)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func inlineSettingRow(title: String, subtitle: String, icon: String, tint: Color, value: String) -> some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColors.tintedBackground(tint, opacity: 0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(AppTypography.caption)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(AppTypography.body)
                Text(subtitle)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }
            Spacer()
            Text(value)
                .font(AppTypography.captionBold)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 3)
                .background(Capsule().fill(tint.opacity(0.14)))
                .foregroundStyle(tint)
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func navigationSummaryRow(title: String, value: String, detail: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColors.tintedBackground(tint, opacity: 0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(AppTypography.caption)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(AppTypography.captionBold)
                    .foregroundStyle(.primary)
                Text(value)
                    .font(AppTypography.body)
                    .foregroundStyle(tint)
                Text(detail)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }
            Spacer(minLength: Spacing.sm)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

enum SettingsConsoleSection: String, CaseIterable, Identifiable {
    case network
    case agent
    case commands
    case users

    var id: String { rawValue }

    var title: String {
        switch self {
        case .network: "网络"
        case .agent: "代理"
        case .commands: "命令"
        case .users: "用户"
        }
    }

    var subtitle: String {
        switch self {
        case .network: "连接测试、诊断链路与调试状态"
        case .agent: "代理配置、系统提示词与行为设置"
        case .commands: "快捷运维命令与完整管理入口"
        case .users: "账号切换、调试与连接测试"
        }
    }

    var icon: String {
        switch self {
        case .network: "network"
        case .agent: "person.crop.circle.fill"
        case .commands: "terminal.fill"
        case .users: "person.crop.circle.fill"
        }
    }
}
