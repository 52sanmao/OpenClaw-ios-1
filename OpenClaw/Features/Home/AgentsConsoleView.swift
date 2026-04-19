import SwiftUI

/// 代理（Agent）控制台 — 与 Web 一致：单一 orchestrator，
/// 展示身份（profile）、当前模型、激活频道、行为开关（auto-approve / planning / allow-local-tools）。
struct AgentsConsoleView: View {
    let adminVM: AdminViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                if let agent = adminVM.agent {
                    identityHero(agent)
                    inferenceBinding(agent)
                    behaviorSwitches(agent)
                    channelsPanel(agent)
                } else if adminVM.isLoading {
                    CardLoadingView(minHeight: 180)
                } else if let error = adminVM.error {
                    CardErrorView(error: error, minHeight: 140)
                } else {
                    ContentUnavailableView(
                        "暂无代理信息",
                        systemImage: "person.2",
                        description: Text("检查网关的 /api/profile 与 /api/settings/export 接口。")
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "代理") {
                    Text(subtitle)
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
            if adminVM.agent == nil && !adminVM.isLoading { await adminVM.load() }
        }
    }

    private var subtitle: String {
        guard let a = adminVM.agent else { return "身份与行为" }
        return "\(a.displayName) · \(a.activatedChannels.count) 个激活频道"
    }

    // MARK: - Identity hero

    @ViewBuilder
    private func identityHero(_ agent: AgentProfile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("Orchestrator 身份")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.metricTertiary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppColors.metricTertiary.opacity(0.12)))
                Spacer()
                Label(agent.role.capitalized, systemImage: "shield.lefthalf.filled")
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.success)
            }

            HStack(alignment: .center, spacing: Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(AppColors.metricTertiary.opacity(0.14))
                        .frame(width: 64, height: 64)
                    Text("🤖")
                        .font(.system(size: 36))
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(agent.displayName)
                        .font(AppTypography.cardTitle)
                    Text(agent.id)
                        .font(AppTypography.captionMono)
                        .foregroundStyle(AppColors.neutral)
                        .lineLimit(1)
                    if let email = agent.email, !email.isEmpty {
                        Text(email)
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
                Spacer(minLength: 0)
            }

            Text("代理统一入口：聊天、定时任务、频道消息最终都路由到这里。")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.neutral)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColors.metricTertiary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Inference binding

    @ViewBuilder
    private func inferenceBinding(_ agent: AgentProfile) -> some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColors.metricPrimary.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "cpu.fill")
                    .foregroundStyle(AppColors.metricPrimary)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("当前推理")
                    .font(AppTypography.captionBold)
                Text(agent.model)
                    .font(AppTypography.captionMono)
                    .foregroundStyle(AppColors.neutral)
                    .lineLimit(1)
            }
            Spacer()
            Text("推理配置")
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.primaryAction)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppColors.primaryAction.opacity(0.1)))
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    // MARK: - Behavior switches

    @ViewBuilder
    private func behaviorSwitches(_ agent: AgentProfile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(AppColors.metricWarm)
                Text("行为开关")
                    .font(AppTypography.captionBold)
                Spacer()
            }
            behaviorRow(
                icon: "checkmark.circle",
                label: "自动批准工具调用",
                subtitle: "auto_approve_tools",
                enabled: agent.autoApproveTools
            )
            behaviorRow(
                icon: "brain.head.profile",
                label: "启用计划模式",
                subtitle: "use_planning",
                enabled: agent.usePlanning
            )
            behaviorRow(
                icon: "wrench.adjustable",
                label: "允许本地工具",
                subtitle: "allow_local_tools",
                enabled: agent.allowLocalTools
            )
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    @ViewBuilder
    private func behaviorRow(icon: String, label: String, subtitle: String, enabled: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill((enabled ? AppColors.success : AppColors.neutral).opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .foregroundStyle(enabled ? AppColors.success : AppColors.neutral)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(AppTypography.body)
                Text(subtitle)
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
            }
            Spacer()
            Text(enabled ? "已开启" : "已关闭")
                .font(AppTypography.nano)
                .foregroundStyle(enabled ? AppColors.success : AppColors.neutral)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(Capsule().fill((enabled ? AppColors.success : AppColors.neutral).opacity(0.1)))
        }
    }

    // MARK: - Activated channels

    @ViewBuilder
    private func channelsPanel(_ agent: AgentProfile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(AppColors.success)
                Text("激活频道")
                    .font(AppTypography.captionBold)
                Spacer()
                Text("\(agent.activatedChannels.count) 个")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }
            if agent.activatedChannels.isEmpty {
                Text("当前没有激活频道 — 去「频道」页安装并配对。")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            } else {
                FlowChipsLayout(spacing: Spacing.xxs) {
                    ForEach(agent.activatedChannels, id: \.self) { channel in
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(AppTypography.nano)
                            Text(channel.capitalized)
                                .font(AppTypography.caption)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppColors.success.opacity(0.12)))
                        .foregroundStyle(AppColors.success)
                    }
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
}

// MARK: - Flow layout used by chips

struct FlowChipsLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if rowWidth + s.width > maxWidth && rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
