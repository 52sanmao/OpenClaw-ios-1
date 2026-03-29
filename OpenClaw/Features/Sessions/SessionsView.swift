import SwiftUI

struct SessionsView: View {
    @State var vm: SessionsViewModel
    let repository: SessionRepository
    var client: GatewayClientProtocol?
    @State private var selectedTab: SessionTab = .chat

    enum SessionTab: String, CaseIterable {
        case chat = "Chat History"
        case subagents = "Subagents"
    }

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            Picker("Session type", selection: $selectedTab) {
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
                DetailTitleView(title: "Sessions") {
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
        if vm.isLoading && vm.mainSession == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let main = vm.mainSession {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    MainSessionCard(session: main, repository: repository, client: client)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .refreshable {
                await vm.load()
                Haptics.shared.refreshComplete()
            }
        } else if let err = vm.error {
            List { CardErrorView(error: err, minHeight: 60) }
                .listStyle(.insetGrouped)
        } else {
            ContentUnavailableView(
                "No Session",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("No active chat session found.")
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
                Section("Subagent Sessions") {
                    ForEach(vm.subagents) { session in
                        NavigationLink {
                            SessionTraceView(
                                sessionKey: session.id,
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
            List { CardErrorView(error: err, minHeight: 60) }
                .listStyle(.insetGrouped)
        } else {
            ContentUnavailableView(
                "No Subagents",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("No subagent sessions found.")
            )
        }
    }

    @ViewBuilder
    private var sessionSubtitle: some View {
        if let main = vm.mainSession {
            HStack(spacing: Spacing.xs) {
                Text(main.status == .running ? "Running" : "Idle")
                    .font(AppTypography.micro)
                    .foregroundStyle(main.status == .running ? AppColors.success : AppColors.neutral)
                Text("\u{00B7} \(Formatters.tokens(main.totalTokens))")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }
        } else if vm.isLoading {
            Text("Loading\u{2026}")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.neutral)
        }
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

                HStack(spacing: Spacing.sm) {
                    if let model = session.model {
                        ModelPill(model: model)
                    }
                    Label(Formatters.tokens(session.totalTokens), systemImage: "number.circle")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.metricPrimary)
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
