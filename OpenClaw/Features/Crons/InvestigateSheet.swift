import MarkdownUI
import SwiftUI

struct InvestigateSheet: View {
    var vm: CronDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var response: ChatCompletionResponse? { vm.investigateResult }
    private var resultText: String? { response?.text }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isInvestigating && response == nil {
                    VStack(spacing: Spacing.md) {
                        ProgressView()
                        Text("Investigating\u{2026}")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.neutral)
                        Text("The agent is checking logs, diagnosing, and fixing if needed.")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Spacing.xl)
                } else if let error = vm.investigateError {
                    ContentUnavailableView(
                        "Investigation Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription)
                    )
                } else if let result = resultText {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            // Header
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "sparkle.magnifyingglass")
                                    .font(AppTypography.statusIcon)
                                    .foregroundStyle(AppColors.metricTertiary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vm.job.name)
                                        .font(AppTypography.body)
                                        .fontWeight(.semibold)
                                    Text("Error Investigation")
                                        .font(AppTypography.micro)
                                        .foregroundStyle(AppColors.neutral)
                                }
                            }

                            // Token usage + model
                            if let usage = response?.usage, let total = usage.totalTokens, total > 0 {
                                HStack(spacing: Spacing.sm) {
                                    if let model = response?.model {
                                        Text(model)
                                            .font(AppTypography.micro)
                                            .padding(.horizontal, Spacing.xs)
                                            .padding(.vertical, 2)
                                            .background(AppColors.pillBackground, in: Capsule())
                                            .foregroundStyle(AppColors.pillForeground)
                                    }
                                    Spacer()
                                    if let prompt = usage.promptTokens {
                                        Label(Formatters.tokens(prompt), systemImage: "tray.and.arrow.down")
                                            .font(AppTypography.micro)
                                            .foregroundStyle(AppColors.neutral)
                                    }
                                    if let completion = usage.completionTokens {
                                        Label(Formatters.tokens(completion), systemImage: "tray.and.arrow.up")
                                            .font(AppTypography.micro)
                                            .foregroundStyle(AppColors.neutral)
                                    }
                                    Label(Formatters.tokens(total), systemImage: "number.circle")
                                        .font(AppTypography.micro)
                                        .foregroundStyle(AppColors.metricPrimary)
                                }
                            }

                            Divider()

                            // Agent report
                            Markdown(result)
                                .markdownTheme(.openClaw)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Copy button
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
                }
            }
            .navigationTitle("Investigation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if resultText != nil {
                        Button { copyResult() } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func copyResult() {
        guard let text = resultText else { return }
        Formatters.copyToClipboard(text, copied: $copied)
    }
}
