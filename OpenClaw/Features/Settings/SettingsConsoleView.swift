import SwiftUI

struct SettingsConsoleView: View {
    let accountStore: AccountStore
    let client: GatewayClientProtocol
    let memoryVM: MemoryViewModel

    @State private var toolsVM: ToolsConfigViewModel
    @State private var adminVM: AdminViewModel
    @State private var selectedSection: SettingsConsoleSection

    init(accountStore: AccountStore, client: GatewayClientProtocol, memoryVM: MemoryViewModel, initialSection: SettingsConsoleSection = .inference) {
        self.accountStore = accountStore
        self.client = client
        self.memoryVM = memoryVM
        _toolsVM = State(initialValue: ToolsConfigViewModel(client: client))
        _adminVM = State(initialValue: AdminViewModel(client: client))
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        List {
            sectionPicker

            switch selectedSection {
            case .inference:
                inferenceSection
            case .agents:
                agentsSection
            case .channels:
                channelsSection
            case .network:
                networkSection
            case .extensions:
                extensionsSection
            case .mcp:
                mcpSection
            case .skills:
                skillsSection
            case .users:
                usersSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "控制台") {
                    Text(selectedSection.subtitle)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .task {
            if adminVM.modelsConfig == nil && !adminVM.isLoading {
                await adminVM.load()
            }
            if toolsVM.config == nil && !toolsVM.isLoading {
                await toolsVM.load()
            }
            if memoryVM.skills.isEmpty && !memoryVM.isLoadingSkills {
                await memoryVM.loadSkills()
            }
        }
        .refreshable {
            async let admin: Void = adminVM.load()
            async let tools: Void = toolsVM.load()
            async let skills: Void = memoryVM.loadSkills()
            _ = await (admin, tools, skills)
            Haptics.shared.refreshComplete()
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
            Text("控制域")
        }
    }

    private var inferenceSection: some View {
        Group {
            if let config = adminVM.modelsConfig {
                Section("推理") {
                    LabeledContent("主模型") {
                        Text(config.defaultModelDisplay)
                            .font(AppTypography.captionBold)
                    }
                    LabeledContent("回退模型") {
                        Text(config.fallbackModelDisplay)
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }
                    LabeledContent("代理数量") {
                        Text("\(adminVM.agents.count)")
                            .font(AppTypography.captionBold)
                    }
                }

                ModelsSection(config: config, agents: adminVM.agents)
            } else {
                Section("推理") {
                    CardLoadingView(minHeight: 100)
                }
            }
        }
    }

    private var agentsSection: some View {
        Section("代理") {
            if adminVM.isLoading && adminVM.agents.isEmpty {
                CardLoadingView(minHeight: 80)
            } else if adminVM.agents.isEmpty {
                Text("当前没有代理信息")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            } else {
                ForEach(adminVM.agents) { agent in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(agent.name)
                            .font(AppTypography.body)
                        Text(agent.model ?? "未配置模型")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }
                    .padding(.vertical, Spacing.xxs)
                }
            }
        }
    }

    private var channelsSection: some View {
        Group {
            if let channels = adminVM.channelsStatus {
                ChannelsSection(status: channels)
            } else {
                Section("频道") {
                    CardLoadingView(minHeight: 80)
                }
            }
        }
    }

    private var networkSection: some View {
        Section("网络") {
            NavigationLink {
                SettingsView(accountStore: accountStore, client: client)
            } label: {
                settingsRow(
                    title: "连接与诊断",
                    subtitle: "测试连接、查看诊断详情与调试状态",
                    icon: "network",
                    tint: AppColors.info
                )
            }

            NavigationLink {
                ToolsConfigView(client: client)
            } label: {
                settingsRow(
                    title: "工具链路",
                    subtitle: "查看工具、配置档与扩展链路状态",
                    icon: "wrench.and.screwdriver",
                    tint: AppColors.metricPrimary
                )
            }
        }
    }

    private var extensionsSection: some View {
        Section("扩展") {
            NavigationLink {
                ToolsConfigView(client: client)
            } label: {
                settingsRow(
                    title: "工具与扩展",
                    subtitle: toolsVM.config?.profile.capitalized ?? "查看已启用配置",
                    icon: "puzzlepiece.extension.fill",
                    tint: AppColors.metricWarm
                )
            }
        }
    }

    private var mcpSection: some View {
        Section("MCP") {
            NavigationLink {
                McpServersView(vm: toolsVM)
            } label: {
                settingsRow(
                    title: "MCP 服务器",
                    subtitle: "\(toolsVM.mcpServers.count) 个服务器",
                    icon: "server.rack",
                    tint: AppColors.metricSecondary
                )
            }
        }
    }

    private var skillsSection: some View {
        Section("技能") {
            NavigationLink {
                SkillsListView(vm: memoryVM)
            } label: {
                settingsRow(
                    title: "技能库",
                    subtitle: memoryVM.skills.isEmpty ? "管理技能与安装来源" : "\(memoryVM.skills.count) 个技能",
                    icon: "bolt.circle.fill",
                    tint: AppColors.metricHighlight
                )
            }
        }
    }

    private var usersSection: some View {
        Section("用户管理") {
            NavigationLink {
                SettingsView(accountStore: accountStore, client: client)
            } label: {
                settingsRow(
                    title: "账号与调试",
                    subtitle: "\(accountStore.accounts.count) 个账号",
                    icon: "person.crop.circle.fill",
                    tint: AppColors.success
                )
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
}

enum SettingsConsoleSection: String, CaseIterable, Identifiable {
    case inference
    case agents
    case channels
    case network
    case extensions
    case mcp
    case skills
    case users

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inference: "推理"
        case .agents: "代理"
        case .channels: "频道"
        case .network: "网络"
        case .extensions: "扩展"
        case .mcp: "MCP"
        case .skills: "技能"
        case .users: "用户管理"
        }
    }

    var subtitle: String {
        switch self {
        case .inference: "模型、后端与默认推理配置"
        case .agents: "查看代理编排与模型归属"
        case .channels: "查看渠道连接与配额状态"
        case .network: "诊断主链路与网络连通性"
        case .extensions: "查看原生工具与扩展配置"
        case .mcp: "管理 MCP 服务器与工具"
        case .skills: "浏览技能库与已安装技能"
        case .users: "账号、调试与连接测试"
        }
    }

    var icon: String {
        switch self {
        case .inference: "cpu.fill"
        case .agents: "person.2.fill"
        case .channels: "bubble.left.and.bubble.right.fill"
        case .network: "network"
        case .extensions: "puzzlepiece.extension.fill"
        case .mcp: "server.rack"
        case .skills: "bolt.circle.fill"
        case .users: "person.crop.circle.fill"
        }
    }
}
