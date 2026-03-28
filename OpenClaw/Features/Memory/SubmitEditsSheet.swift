import MarkdownUI
import SwiftUI

struct SubmitEditsSheet: View {
    var vm: MemoryViewModel
    let file: MemoryFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Your Comments (\(vm.comments.count))") {
                    ForEach(vm.comments) { comment in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Lines \(comment.lineStart + 1)\u{2013}\(comment.lineEnd + 1)")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                            Text(comment.text)
                                .font(AppTypography.body)
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                }

                if let response = vm.submitResult {
                    Section("Agent Response") {
                        Markdown(response)
                            .markdownTheme(.openClaw)
                            .textSelection(.enabled)
                    }
                }

                if let error = vm.submitError {
                    Section {
                        Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.danger)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Submit Edits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.submitResult != nil {
                        Button("Done") {
                            vm.clearComments()
                            dismiss()
                            Task { await vm.loadFile(file) }
                        }
                    } else {
                        Button {
                            Task { await vm.submitEdits(for: file) }
                        } label: {
                            if vm.isSubmitting {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text("Submit")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(vm.isSubmitting)
                    }
                }
            }
        }
    }
}
