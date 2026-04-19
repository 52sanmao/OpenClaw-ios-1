import SwiftUI

/// 代理配置视图 — 对齐 Web 端的代理管理功能
/// 支持代理选择、系统提示词编辑、行为配置
struct AgentSettingsView: View {
    let adminVM: AdminViewModel

    @State private var selectedAgentId: String?
    @State private var editingPrompt = false
    @State private var draftPrompt = ""
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                currentAgentCard

                if !adminVM.agents.isEmpty {
                    agentListSection
                }

                if let agent = adminVM.agent {
                    systemPromptSection(agent)
                    behaviorSection(agent)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "代理配置") {
                    Text(adminVM.agent?.displayName ?? "未选择")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .refreshable {
            await adminVM.load()
            Haptics.shared.refreshComplete()
        }
        .task {
            if adminVM.agents.isEmpty && !adminVM.isLoading {
                await adminVM.load()
            }
        }
        .sheet(isPresented: $editingPrompt) {
            systemPromptEditor
        }
        .alert("保存失败", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好的", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Current Agent Card

    @ViewBuilder
    private var currentAgentCard: some View {
        if let agent = adminVM.agent {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Text("当前代理")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.success)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.success.opacity(0.12)))
                    Spacer()
                }

                HStack(alignment: .center, spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(AppColors.success.opacity(0.14))
                            .frame(width: 64, height: 64)
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(AppColors.success)
                    }
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(agent.displayName)
                            .font(AppTypography.cardTitle)
                        if let desc = agent.description, !desc.isEmpty {
                            Text(desc)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.neutral)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColors.success.opacity(0.18), lineWidth: 1)
            )
        }
    }

    // MARK: - Agent List

    @ViewBuilder
    private var agentListSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(AppColors.metricTertiary)
                Text("可用代理")
                    .font(AppTypography.captionBold)
                Spacer()
                Text("\(adminVM.agents.count) 个")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            VStack(spacing: Spacing.xs) {
                ForEach(adminVM.agents) { agent in
                    agentRow(agent)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    @ViewBuilder
    private func agentRow(_ agent: AgentDTO) -> some View {
        let isActive = agent.id == adminVM.agent?.id

        Button {
            Task { await switchAgent(agent) }
        } label: {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill((isActive ? AppColors.success : AppColors.neutral).opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: isActive ? "checkmark.circle.fill" : "person.circle")
                        .foregroundStyle(isActive ? AppColors.success : AppColors.neutral)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Spacing.xxs) {
                        Text(agent.displayName)
                            .font(AppTypography.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if isActive {
                            Text("使用中")
                                .font(AppTypography.nano)
                                .padding(.horizontal, Spacing.xxs)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(AppColors.success.opacity(0.15)))
                                .foregroundStyle(AppColors.success)
                        }
                    }
                    if let desc = agent.description, !desc.isEmpty {
                        Text(desc)
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !isActive {
                    Text("切换")
                        .font(AppTypography.nano)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.primaryAction)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(isActive ? AppColors.success.opacity(0.05) : Color(.systemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(isActive)
    }

    // MARK: - System Prompt

    @ViewBuilder
    private func systemPromptSection(_ agent: AgentDTO) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(AppColors.info)
                Text("系统提示词")
                    .font(AppTypography.captionBold)
                Spacer()
                Button {
                    draftPrompt = agent.systemPrompt ?? ""
                    editingPrompt = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                        .font(AppTypography.nano)
                        .fontWeight(.semibold)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppColors.info.opacity(0.12)))
                        .foregroundStyle(AppColors.info)
                }
                .buttonStyle(.plain)
            }

            if let prompt = agent.systemPrompt, !prompt.isEmpty {
                Text(prompt)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.neutral)
                    .lineLimit(5)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .fill(Color(.systemGroupedBackground))
                    )
            } else {
                Text("未设置系统提示词")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.neutral)
                    .italic()
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    @ViewBuilder
    private var systemPromptEditor: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $draftPrompt)
                    .font(AppTypography.body)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("编辑系统提示词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        editingPrompt = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveSystemPrompt() }
                    } label: {
                        if saving {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Text("保存").fontWeight(.semibold)
                        }
                    }
                    .disabled(saving)
                }
            }
        }
    }

    // MARK: - Behavior

    @ViewBuilder
    private func behaviorSection(_ agent: AgentDTO) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(AppColors.metricPrimary)
                Text("行为配置")
                    .font(AppTypography.captionBold)
                Spacer()
            }

            VStack(spacing: Spacing.xs) {
                behaviorRow(icon: "brain.head.profile", label: "记忆", value: "启用")
                behaviorRow(icon: "bolt.circle.fill", label: "技能", value: "启用")
                behaviorRow(icon: "wrench.and.screwdriver", label: "工具", value: "启用")
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    @ViewBuilder
    private func behaviorRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.metricPrimary)
                .frame(width: 24)
            Text(label)
                .font(AppTypography.body)
            Spacer()
            Text(value)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.neutral)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(Color(.systemGroupedBackground))
        )
    }

    // MARK: - Actions

    private func switchAgent(_ agent: AgentDTO) async {
        do {
            try await adminVM.setActiveAgent(id: agent.id)
            await adminVM.load()
            Haptics.shared.success()
        } catch {
            saveError = error.localizedDescription
            Haptics.shared.error()
        }
    }

    private func saveSystemPrompt() async {
        saving = true
        defer { saving = false }
        do {
            // TODO: Implement system prompt update API
            // try await adminVM.updateAgentSystemPrompt(draftPrompt)
            editingPrompt = false
            Haptics.shared.success()
        } catch {
            saveError = error.localizedDescription
            Haptics.shared.error()
        }
    }
}
