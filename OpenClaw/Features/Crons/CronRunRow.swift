import MarkdownUI
import SwiftUI

struct CronRunRow: View {
    let run: CronRun
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Top line: status + time + duration + chevron
            Button(action: onTap) {
                HStack(spacing: Spacing.xs) {
                    CronStatusDot(status: run.status)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.runAtFormatted)
                            .font(AppTypography.body)
                        Text(run.runAtAbsolute)
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }

                    Spacer()

                    Label(run.durationFormatted, systemImage: "timer")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)

                    Image(systemName: "chevron.down")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            // Always visible: model + total tokens
            HStack(spacing: Spacing.sm) {
                if let model = run.model {
                    Text(Formatters.modelShortName(model))
                        .font(AppTypography.micro)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(AppColors.pillBackground, in: Capsule())
                        .foregroundStyle(AppColors.pillForeground)
                }

                Spacer()

                Label(Formatters.tokens(run.totalTokens), systemImage: "number.circle")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.metricPrimary)
            }

            // Always visible: token breakdown bar
            TokenBreakdownBar(
                input: run.inputTokens,
                output: run.outputTokens,
                total: run.totalTokens
            )

            // Expanded: summary markdown
            if isExpanded {
                if let summary = run.summary, !summary.isEmpty {
                    Divider()
                    Markdown(summary)
                        .markdownTheme(.openClaw)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}



