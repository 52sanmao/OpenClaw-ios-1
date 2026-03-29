import MarkdownUI
import SwiftUI

/// Batch review + submit sheet for trace step comments.
struct TraceCommentsSheet: View {
    let sessionKey: String
    let sessionTitle: String
    let client: GatewayClientProtocol
    @Binding var comments: [TraceComment]
    @Environment(\.dismiss) private var dismiss

    @State private var isSubmitting = false
    @State private var result: String?
    @State private var submitError: Error?

    var body: some View {
        NavigationStack {
            List {
                if result == nil {
                    Section("Your Comments (\(comments.count))") {
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack {
                                    Text(comment.stepTitle)
                                        .font(AppTypography.captionBold)
                                    Spacer()
                                    if let ts = comment.stepTimestamp {
                                        Text(ts)
                                            .font(AppTypography.micro)
                                            .foregroundStyle(AppColors.neutral)
                                    }
                                }
                                Text(comment.stepPreview)
                                    .font(AppTypography.micro)
                                    .foregroundStyle(AppColors.neutral)
                                    .lineLimit(2)
                                Text(comment.text)
                                    .font(AppTypography.body)
                            }
                            .padding(.vertical, Spacing.xxs)
                        }
                        .onDelete { indexSet in
                            let ids = indexSet.map { comments[$0].id }
                            ids.forEach { id in comments.removeAll { $0.id == id } }
                            if comments.isEmpty { dismiss() }
                        }
                    }
                }

                if isSubmitting {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: Spacing.xs) {
                                ProgressView()
                                Text("Agent is investigating\u{2026}")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.neutral)
                                ElapsedTimer()
                            }
                            Spacer()
                        }
                        .padding(.vertical, Spacing.md)
                    }
                }

                if let response = result {
                    Section("Agent Response") {
                        Markdown(response)
                            .markdownTheme(.openClaw)
                            .textSelection(.enabled)
                    }
                }

                if let error = submitError {
                    Section {
                        Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.danger)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Trace Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if result != nil {
                        Button("Done") {
                            comments.removeAll()
                            dismiss()
                        }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if result == nil {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isSubmitting {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text("Submit")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(isSubmitting || comments.isEmpty)
                    }
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        submitError = nil

        let prompt = PromptTemplates.investigateTrace(
            sessionKey: sessionKey,
            sessionTitle: sessionTitle,
            comments: comments
        )
        let request = ChatCompletionRequest(system: prompt.system, user: prompt.user)

        do {
            let response = try await client.chatCompletion(request, sessionKey: SessionKeys.main)
            result = response.text ?? "Agent returned no content."
            Haptics.shared.success()
        } catch {
            submitError = error
            Haptics.shared.error()
        }
        isSubmitting = false
    }
}
