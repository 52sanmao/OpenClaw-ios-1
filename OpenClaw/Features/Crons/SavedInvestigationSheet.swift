import MarkdownUI
import SwiftUI

struct SavedInvestigationSheet: View {
    let investigation: SavedInvestigation
    @Environment(\.dismiss) private var dismiss

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
                                ModelPill(model: model)
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

                    CopyButton(investigation.resultText, label: "Copy Report")
                }
                .padding(Spacing.md)
            }
            .navigationTitle("Previous Investigation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CopyToolbarButton(text: investigation.resultText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
