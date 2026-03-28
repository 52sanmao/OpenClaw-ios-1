import MarkdownUI
import SwiftUI

struct MemoryFileView: View {
    var vm: MemoryViewModel
    let file: MemoryFile
    /// Optional skill entry — when set, uses skill-read instead of memory_get.
    var skillEntry: SkillFileEntry?
    @State private var commentTarget: MemoryParagraph?
    @State private var showSubmitSheet = false
    @State private var showPageComment = false

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
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: Spacing.sm) {
                    Button { showPageComment = true } label: {
                        Image(systemName: "text.bubble")
                    }
                    if !vm.comments.isEmpty {
                        Button { showSubmitSheet = true } label: {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "paperplane.fill")
                                Text("\(vm.comments.count)")
                            }
                            .foregroundStyle(AppColors.primaryAction)
                        }
                    }
                }
            }
        }
        .sheet(item: $commentTarget) { para in
            CommentSheet(mode: .paragraph(preview: para.text) { text in
                vm.addComment(
                    paragraphId: para.id,
                    lineStart: para.lineStart,
                    lineEnd: para.lineEnd,
                    text: text,
                    preview: para.text
                )
            })
        }
        .sheet(isPresented: $showSubmitSheet) {
            SubmitEditsSheet(vm: vm, file: file, skillEntry: skillEntry)
        }
        .sheet(isPresented: $showPageComment) {
            CommentSheet(mode: .page(fileName: file.name, filePath: file.path, vm: vm))
        }
        .task {
            if let entry = skillEntry {
                await vm.loadSkillFileContent(entry)
            } else {
                await vm.loadFile(file)
            }
        }
    }
}

// MARK: - Paragraph Row

struct ParagraphRow: View {
    let paragraph: MemoryParagraph
    let comments: [MemoryComment]
    let onAddComment: () -> Void
    let onRemoveComment: (UUID) -> Void

    private var hasComments: Bool { !comments.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(hasComments ? AppColors.metricWarm : .clear)
                .frame(width: 3)
                .padding(.vertical, Spacing.xs)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Markdown(paragraph.text)
                    .markdownTheme(.openClaw)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        hasComments
                            ? AppColors.tintedBackground(AppColors.metricWarm, opacity: 0.06)
                            : .clear,
                        in: RoundedRectangle(cornerRadius: AppRadius.sm)
                    )

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
                        .accessibilityLabel("Remove comment")
                    }
                    .padding(Spacing.xs)
                    .background(AppColors.tintedBackground(AppColors.metricWarm, opacity: 0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))
                }

                Button(action: onAddComment) {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "plus.bubble")
                        Text(hasComments ? "Add Another" : "Add Comment")
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.primaryAction)
                    .padding(.vertical, Spacing.xxs)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
        .padding(.horizontal, Spacing.xs)
    }
}
