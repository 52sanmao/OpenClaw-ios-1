import SwiftUI

/// Read-only monospace viewer for non-markdown files (scripts, JSON, config).
struct ReadOnlyFileView: View {
    var vm: MemoryViewModel
    let entry: SkillFileEntry
    @State private var showPageComment = false

    var body: some View {
        Group {
            if vm.isLoadingContent || (vm.fileContent == nil && vm.contentError == nil) {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.contentError {
                ContentUnavailableView(
                    "无法加载内容",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            } else if let content = vm.fileContent {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(content.text)
                            .font(AppTypography.captionMono)
                            .textSelection(.enabled)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { showPageComment = true }

                        Text("点击正文即可添加整页批注")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.primaryAction)
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, Spacing.sm)
                    }
                }
                .background(AppColors.neutral.opacity(0.04))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: entry.name) {
                    Text(entry.id)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                if let content = vm.fileContent {
                    CopyToolbarButton(text: content.text)
                }
            }
        }
        .sheet(isPresented: $showPageComment) {
            CommentSheet(mode: .page(fileName: entry.name, filePath: entry.absolutePath, vm: vm))
        }
        .task { await vm.loadSkillFileContent(entry) }
    }
}
