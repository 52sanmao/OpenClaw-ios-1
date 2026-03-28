import MarkdownUI
import SwiftUI

struct SavedInvestigationSheet: View {
    let investigation: SavedInvestigation
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Header
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(AppTypography.statusIcon)
                            .foregroundStyle(AppColors.neutral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(investigation.jobName)
                                .font(AppTypography.body)
                                .fontWeight(.semibold)
                            Text("Investigated \(investigation.investigatedAtFormatted)")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                        }
                    }

                    // Token usage
                    if let total = investigation.totalTokens, total > 0 {
                        HStack(spacing: Spacing.sm) {
                            if let model = investigation.model {
                                Text(model)
                                    .font(AppTypography.micro)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(AppColors.pillBackground, in: Capsule())
                                    .foregroundStyle(AppColors.pillForeground)
                            }
                            Spacer()
                            Label(Formatters.tokens(total), systemImage: "number.circle")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.metricPrimary)
                        }
                    }

                    Divider()

                    Markdown(investigation.resultText)
                        .markdownTheme(.openClaw)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button { copyResult() } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied" : "Copy Report")
                        }
                        .font(AppTypography.caption)
                        .foregroundStyle(copied ? AppColors.success : AppColors.primaryAction)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            AppColors.tintedBackground(copied ? AppColors.success : AppColors.primaryAction),
                            in: RoundedRectangle(cornerRadius: AppRadius.sm)
                        )
                    }
                }
                .padding(Spacing.md)
            }
            .navigationTitle("Previous Investigation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { copyResult() } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func copyResult() {
        Formatters.copyToClipboard(investigation.resultText, copied: $copied)
    }
}
