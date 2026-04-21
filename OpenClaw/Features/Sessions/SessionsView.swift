import SwiftUI

struct SessionsView: View {
    @State var vm: SessionsViewModel
    let repository: SessionRepository
    var client: GatewayClientProtocol?
    @State private var selectedTab: SessionTab = .chat

    enum SessionTab: String, CaseIterable {
        case chat = "聊天历史"
        case subagents = "子代理"
    }

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            Picker("会话类型", selection: $selectedTab) {
                ForEach(SessionTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)

            switch selectedTab {
            case .chat:
                chatSection
            case .subagents:
                subagentsSection
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "会话") {
                    sessionSubtitle
                }
            }
        }
        }
        .task { await vm.load() }
    }

    // MARK: - Chat History

    @ViewBuilder
    private var chatSection: some View {
        if vm.isLoading && vm.chatSessions.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !vm.chatSessions.isEmpty {
            List {
                Section("聊天历史") {
                    ForEach(vm.chatSessions) { session in
                        NavigationLink {
                            SessionTraceView(
                                sessionKey: session.traceLookupKey,
                                title: session.displayName,
                                subtitle: session.startedAtFormatted,
                                newestFirst: true,
                                repository: repository,
                                client: client
                            )
                        } label: {
                            ChatHistoryRow(session: session)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await vm.load()
                Haptics.shared.refreshComplete()
            }
        } else if let err = vm.error {
            List {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    CardErrorView(error: err, minHeight: 60)
                    Text("会话页优先使用 sessions_list / sessions_history；若服务器未启用扩展接口，会自动回退到 /api/chat/threads 与 /api/chat/history。请查看右下角日志确认当前走的是哪条路径。")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
                .padding(.vertical, Spacing.xxs)
            }
            .listStyle(.insetGrouped)
        } else {
            ContentUnavailableView(
                "暂无会话",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("未找到活动中的聊天会话。")
            )
        }
    }

    // MARK: - Subagents

    @ViewBuilder
    private var subagentsSection: some View {
        if vm.isLoading && vm.subagents.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !vm.subagents.isEmpty {
            List {
                Section("子代理会话") {
                    ForEach(vm.subagents) { session in
                        NavigationLink {
                            SessionTraceView(
                                sessionKey: session.traceLookupKey,
                                title: session.displayName,
                                subtitle: session.updatedAtFormatted,
                                repository: repository,
                                client: client
                            )
                        } label: {
                            SubagentRow(session: session)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await vm.load()
                Haptics.shared.refreshComplete()
            }
        } else if let err = vm.error {
            List {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    CardErrorView(error: err, minHeight: 60)
                    Text("子代理列表与轨迹页同样支持从扩展接口回退到线程历史。请查看右下角日志，确认失败发生在 sessions_list、sessions_history 还是底层 /api/chat/history。")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
                .padding(.vertical, Spacing.xxs)
            }
            .listStyle(.insetGrouped)
        } else {
            ContentUnavailableView(
                "暂无子代理",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("未找到子代理会话。")
            )
        }
    }

    @ViewBuilder
    private var sessionSubtitle: some View {
        if let latest = vm.chatSessions.first {
            HStack(spacing: Spacing.xs) {
                Text(latest.status == .running ? "运行中" : "最近聊天")
                    .font(AppTypography.micro)
                    .foregroundStyle(latest.status == .running ? AppColors.success : AppColors.neutral)
                Text("· \(vm.chatSessions.count) 条会话")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }
        } else if vm.isLoading {
            Text("加载中…")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.neutral)
        }
    }
}

// MARK: - Chat History Row

private struct ChatHistoryRow: View {
    let session: SessionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text(session.displayName)
                    .font(AppTypography.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if session.kind == .main {
                    Text("当前主聊天")
                        .font(AppTypography.nano)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.vertical, 2)
                        .background(AppColors.success.opacity(0.14), in: Capsule())
                        .foregroundStyle(AppColors.success)
                }
                Spacer()
                Text(session.updatedAtFormatted)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            if !session.contextBadges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(session.contextBadges, id: \.self) { badge in
                            Text(badge)
                                .font(AppTypography.nano)
                                .padding(.horizontal, Spacing.xxs)
                                .padding(.vertical, 3)
                                .background(AppColors.primaryAction.opacity(0.1), in: Capsule())
                                .foregroundStyle(AppColors.primaryAction)
                        }
                        if session.isReadOnlyChannel {
                            Text("只读")
                                .font(AppTypography.nano)
                                .padding(.horizontal, Spacing.xxs)
                                .padding(.vertical, 3)
                                .background(AppColors.warning.opacity(0.12), in: Capsule())
                                .foregroundStyle(AppColors.warning)
                        }
                    }
                }
            }

            HStack(spacing: Spacing.sm) {
                if let model = session.model {
                    ModelPill(model: model)
                }
                Label(Formatters.tokens(session.totalTokens), systemImage: "number.circle")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.metricPrimary)
                Text(session.status == .running ? "运行中" : (session.isReadOnlyChannel ? "查看历史" : "继续对话"))
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
                Spacer()
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Subagent Row

private struct SubagentRow: View {
    let session: SessionEntry

    var body: some View {
        HStack(spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(session.displayName)
                    .font(AppTypography.body)
                    .lineLimit(1)

                if !session.contextBadges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xs) {
                            ForEach(session.contextBadges, id: \.self) { badge in
                                Text(badge)
                                    .font(AppTypography.nano)
                                    .padding(.horizontal, Spacing.xxs)
                                    .padding(.vertical, 3)
                                    .background(AppColors.metricTertiary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(AppColors.metricTertiary)
                            }
                        }
                    }
                }

                HStack(spacing: Spacing.sm) {
                    if let model = session.model {
                        ModelPill(model: model)
                    }
                    Label(Formatters.tokens(session.totalTokens), systemImage: "number.circle")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.metricPrimary)
                    Text(session.status == .running ? "运行中" : "查看轨迹")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    Spacer()
                    Text(session.updatedAtFormatted)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
