import MarkdownUI
import SwiftUI

struct MemoryFileView: View {
    var vm: MemoryViewModel
    let file: MemoryFile
    @State private var commentTarget: MemoryParagraph?
    @State private var showSubmitSheet = false

    var body: some View {
        Group {
            if vm.isLoadingContent || (vm.fileContent == nil && vm.contentError == nil) {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.contentError {
                ContentUnavailableView(
                    "Cannot Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            } else if let content = vm.fileContent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(content.paragraphs) { para in
                            ParagraphRow(
                                paragraph: para,
                                comments: vm.commentsForParagraph(para.id),
                                onAddComment: { commentTarget = para },
                                onRemoveComment: { vm.removeComment($0) }
                            )
                            Divider().padding(.horizontal, Spacing.md)
                        }
                    }
                }
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !vm.comments.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showSubmitSheet = true
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "paperplane.fill")
                            Text("\(vm.comments.count)")
                        }
                        .foregroundStyle(AppColors.primaryAction)
                    }
                }
            }
        }
        .sheet(item: $commentTarget) { para in
            AddCommentSheet(paragraphPreview: para.text) { text in
                vm.addComment(
                    paragraphId: para.id,
                    lineStart: para.lineStart,
                    lineEnd: para.lineEnd,
                    text: text,
                    preview: para.text
                )
                commentTarget = nil
            }
        }
        .sheet(isPresented: $showSubmitSheet) {
            SubmitEditsSheet(vm: vm, file: file)
        }
        .task { await vm.loadFile(file) }
    }
}

// MARK: - Paragraph Row

private struct ParagraphRow: View {
    let paragraph: MemoryParagraph
    let comments: [MemoryComment]
    let onAddComment: () -> Void
    let onRemoveComment: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Content
            Markdown(paragraph.text)
                .markdownTheme(.openClaw)
                .textSelection(.enabled)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

            // Comments on this paragraph
            ForEach(comments) { comment in
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: "text.bubble.fill")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.metricWarm)
                    Text(comment.text)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.metricWarm)
                    Spacer()
                    Button { onRemoveComment(comment.id) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Spacing.xs)
                .background(AppColors.tintedBackground(AppColors.metricWarm, opacity: 0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))
                .padding(.horizontal, Spacing.md)
            }

            // Add comment button
            Button(action: onAddComment) {
                Label("Comment", systemImage: "plus.bubble")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xs)
        }
    }
}

// MARK: - Add Comment Sheet

private struct AddCommentSheet: View {
    let paragraphPreview: String
    let onSubmit: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Preview of paragraph
                Text(String(paragraphPreview.prefix(200)))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.neutral)
                    .lineLimit(4)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.neutral.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.sm))

                // Comment input
                TextField("What should change here\u{2026}", text: $text, axis: .vertical)
                    .font(AppTypography.body)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)

                Spacer()
            }
            .padding(Spacing.md)
            .navigationTitle("Add Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = text.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSubmit(trimmed)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
