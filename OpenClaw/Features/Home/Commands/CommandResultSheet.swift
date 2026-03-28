import MarkdownUI
import SwiftUI

struct CommandResultSheet: View {
    let result: CommandResult
    var vm: CommandsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Status header
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(AppTypography.statusIcon)
                            .foregroundStyle(result.isSuccess ? AppColors.success : AppColors.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.command.name)
                                .font(AppTypography.body)
                                .fontWeight(.semibold)
                            Text(result.isSuccess ? "Completed" : "Failed")
                                .font(AppTypography.micro)
                                .foregroundStyle(result.isSuccess ? AppColors.success : AppColors.danger)
                        }
                    }

                    Divider()

                    // Command output
                    Text(result.output)
                        .font(AppTypography.captionMono)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.sm)
                        .background(AppColors.neutral.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))

                    // Action buttons
                    HStack(spacing: Spacing.sm) {
                        // Copy
                        Button { Formatters.copyToClipboard(result.output, copied: $copied) } label: {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "Copied" : "Copy")
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

                        // Investigate with AI
                        Button {
                            Task { await vm.investigateResult(result) }
                        } label: {
                            HStack(spacing: Spacing.xxs) {
                                if vm.isInvestigating {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: "sparkle.magnifyingglass")
                                }
                                Text("Investigate")
                            }
                            .font(AppTypography.caption)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xs)
                            .background(AppColors.metricTertiary, in: RoundedRectangle(cornerRadius: AppRadius.sm))
                        }
                        .disabled(vm.isInvestigating)
                    }

                    // AI investigation result
                    if vm.isInvestigating && vm.investigateResponse == nil {
                        VStack(spacing: Spacing.xs) {
                            ElapsedTimer()
                            Text("Agent is analysing output\u{2026}")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                    }

                    if let response = vm.investigateResponse {
                        Divider()

                        // Token info
                        if let usage = response.usage, let total = usage.totalTokens, total > 0 {
                            HStack(spacing: Spacing.sm) {
                                if let model = response.model {
                                    ModelPill(model: model)
                                }
                                Spacer()
                                Label(Formatters.tokens(total), systemImage: "number.circle")
                                    .font(AppTypography.micro)
                                    .foregroundStyle(AppColors.metricPrimary)
                            }
                        }

                        // AI report
                        Markdown(response.text ?? "No response.")
                            .markdownTheme(.openClaw)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = vm.investigateError {
                        Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.danger)
                    }
                }
                .padding(Spacing.md)
            }
            .navigationTitle("Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CopyToolbarButton(text: result.output)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
