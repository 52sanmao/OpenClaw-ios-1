import SwiftUI

/// Hero card for the main orchestrator session.
struct MainSessionCard: View {
    let session: SessionEntry
    let repository: SessionRepository
    var client: GatewayClientProtocol?

    var body: some View {
        NavigationLink {
            SessionTraceView(
                sessionKey: session.id,
                title: "Main Session",
                subtitle: session.startedAtFormatted,
                newestFirst: true,
                repository: repository,
                client: client
            )
        } label: {
            VStack(spacing: Spacing.lg) {
                // Status + model
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Main Session")
                            .font(AppTypography.heroNumber)
                        HStack(spacing: Spacing.xs) {
                            Circle()
                                .fill(session.status == .running ? AppColors.success : AppColors.neutral)
                                .frame(width: 8, height: 8)
                            Text(session.status == .running ? "Running" : "Idle")
                                .font(AppTypography.caption)
                                .foregroundStyle(session.status == .running ? AppColors.success : AppColors.neutral)
                        }
                    }
                    Spacer()
                    if let model = session.model {
                        ModelPill(model: model)
                    }
                }

                // Context ring gauge
                HStack(spacing: Spacing.xl) {
                    RingGauge(
                        value: session.contextUsage,
                        label: "Context",
                        color: AppColors.gauge(
                            percent: session.contextUsage * 100,
                            warn: 60,
                            critical: 80
                        )
                    )

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        MetricRow(icon: "number.circle", label: "Tokens", value: Formatters.tokens(session.totalTokens), color: AppColors.metricPrimary)
                        MetricRow(icon: "dollarsign.circle", label: "Cost", value: Formatters.cost(session.costUsd), color: AppColors.metricWarm)
                        MetricRow(icon: "point.3.connected.trianglepath.dotted", label: "Subagents", value: "\(session.childSessionCount)", color: AppColors.neutral)
                        MetricRow(icon: "clock", label: "Updated", value: session.updatedAtFormatted, color: AppColors.neutral)
                    }
                }

                // Context detail
                HStack(spacing: Spacing.sm) {
                    Text(Formatters.tokens(session.totalTokens))
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.metricPrimary)
                    Text("/")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    Text(Formatters.tokens(session.contextTokens))
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    Text("context window")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    Spacer()
                    HStack(spacing: Spacing.xxs) {
                        Text("View Trace")
                            .font(AppTypography.caption)
                        Image(systemName: "chevron.right")
                            .font(AppTypography.micro)
                    }
                    .foregroundStyle(AppColors.primaryAction)
                }
            }
            .padding(Spacing.md)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card)
                    .strokeBorder(AppColors.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to view execution trace")
    }
}

private struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(AppTypography.micro)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(value)
                .font(AppTypography.captionBold)
                .foregroundStyle(color)
            Text(label)
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.neutral)
        }
    }
}
