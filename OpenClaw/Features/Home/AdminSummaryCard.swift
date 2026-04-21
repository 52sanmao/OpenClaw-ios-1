import SwiftUI

/// Admin dashboard summary card — mirrors the web admin dashboard metric strip.
/// Shows total users, 30d LLM calls, and 30d cost at a glance.
struct AdminSummaryCard: View {
    @Bindable var vm: AdminSummaryViewModel

    var body: some View {
        CardContainer(
            title: "运维概览",
            systemImage: "chart.bar.fill",
            isStale: vm.isStale,
            isLoading: vm.isLoading && vm.data == nil
        ) {
            if let summary = vm.data {
                content(summary)
            } else if vm.isLoading {
                CardLoadingView(minHeight: 80)
            } else if let err = vm.error {
                CardErrorView(error: err, minHeight: 80)
            }
        }
    }

    @ViewBuilder
    private func content(_ s: AdminUsageSummaryDTO) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                metricTile(
                    icon: "person.2.fill",
                    value: "\(s.users?.total ?? 0)",
                    label: "用户",
                    detail: "\(s.users?.active ?? 0) 活跃",
                    tint: AppColors.metricPrimary
                )
                metricTile(
                    icon: "cpu",
                    value: "\(s.usage30d?.llmCalls ?? 0)",
                    label: "30d 调用",
                    detail: "LLM",
                    tint: AppColors.metricTertiary
                )
                metricTile(
                    icon: "dollarsign.circle.fill",
                    value: formatCost(s.usage30d?.totalCost),
                    label: "30d 成本",
                    detail: "累计",
                    tint: AppColors.metricWarm
                )
            }
            HomeCardDetailHint()
        }
    }

    @ViewBuilder
    private func metricTile(icon: String, value: String, label: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: icon)
                    .font(AppTypography.nano)
                    .foregroundStyle(tint)
                Text(label)
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
            }
            Text(value)
                .font(AppTypography.cardTitle)
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(detail)
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
                .lineLimit(1)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColors.tintedBackground(tint, opacity: 0.06))
        )
    }

    private func formatCost(_ raw: String?) -> String {
        guard let s = raw, let v = Double(s) else { return "$0.00" }
        return String(format: "$%.2f", v)
    }
}
