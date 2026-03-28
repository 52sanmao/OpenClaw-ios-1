import SwiftUI

struct CronHistoryRow: View {
    let run: CronRun
    let jobName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Top: job name + status badge
            HStack(spacing: Spacing.xs) {
                CronStatusDot(status: run.status)
                Text(jobName ?? run.jobId)
                    .font(AppTypography.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(run.durationFormatted)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            // Time
            HStack(spacing: Spacing.sm) {
                Text(run.runAtFormatted)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.neutral)
                Text(run.runAtAbsolute)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            // Model + tokens
            HStack(spacing: Spacing.sm) {
                if let model = run.model {
                    ModelPill(model: model)
                }

                Spacer()

                Label(Formatters.tokens(run.totalTokens), systemImage: "number.circle")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.metricPrimary)
            }

            TokenBreakdownBar(
                input: run.inputTokens,
                output: run.outputTokens,
                total: run.totalTokens
            )
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

}
