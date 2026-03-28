import MarkdownUI
import SwiftUI

struct SubmitEditsSheet: View {
    var vm: MemoryViewModel
    let file: MemoryFile
    var skillEntry: SkillFileEntry?
    @Environment(\.dismiss) private var dismiss

    private var hasResult: Bool { vm.submitResult != nil }

    var body: some View {
        NavigationStack {
            List {
                // Comment queue — swipe to delete before submitting
                if !hasResult {
                    Section("Your Comments (\(vm.comments.count))") {
                        ForEach(vm.comments) { comment in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(comment.lineStart == comment.lineEnd
                                     ? "Line \(comment.lineStart + 1)"
                                     : "Lines \(comment.lineStart + 1)\u{2013}\(comment.lineEnd + 1)")
                                    .font(AppTypography.micro)
                                    .foregroundStyle(AppColors.neutral)
                                Text(comment.paragraphPreview)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.neutral)
                                    .lineLimit(2)
                                Text(comment.text)
                                    .font(AppTypography.body)
                            }
                            .padding(.vertical, Spacing.xxs)
                        }
                        .onDelete { indexSet in
                            let ids = indexSet.map { vm.comments[$0].id }
                            ids.forEach { vm.removeComment($0) }
                            if vm.comments.isEmpty { dismiss() }
                        }
                    }
                }

                if vm.isSubmitting {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: Spacing.xs) {
                                ProgressView()
                                Text("Agent is editing\u{2026}")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.neutral)
                                ElapsedTimer()
                            }
                            Spacer()
                        }
                        .padding(.vertical, Spacing.md)
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
                    if hasResult {
                        Button("Done") {
                            vm.clearComments()
                            dismiss()
                            Task { await reloadFile() }
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
                        .disabled(vm.isSubmitting || vm.comments.isEmpty)
                    }
                }
            }
        }
    }

    private func reloadFile() async {
        if let entry = skillEntry {
            await vm.loadSkillFileContent(entry)
        } else {
            await vm.loadFile(file)
        }
    }
}
