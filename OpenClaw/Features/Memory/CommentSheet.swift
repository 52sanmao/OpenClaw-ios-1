import MarkdownUI
import SwiftUI

/// Unified comment sheet — handles both paragraph-level and page-level comments.
struct CommentSheet: View {
    let mode: Mode
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        /// Paragraph comment — shows preview, submits locally via callback.
        case paragraph(preview: String, onSubmit: (String) -> Void)
        /// Page comment — shows file info, submits to agent.
        case page(fileName: String, filePath: String, vm: MemoryViewModel)
    }

    private var title: String {
        switch mode {
        case .paragraph: "Add Comment"
        case .page: "Page Comment"
        }
    }

    /// Whether the page-mode agent has started or finished.
    private var pageHasActivity: Bool {
        guard case .page(_, _, let vm) = mode else { return false }
        return vm.isSubmittingPageComment || vm.pageCommentResult != nil || vm.pageCommentError != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch mode {
                case .paragraph(let preview, _):
                    paragraphContent(preview: preview)
                case .page(let fileName, let filePath, let vm):
                    pageContent(fileName: fileName, filePath: filePath, vm: vm)
                }

                // Input bar — hidden once page submission has started
                if !pageHasActivity {
                    CommentInputBar(
                        placeholder: inputPlaceholder,
                        text: $text
                    ) { submitted in
                        handleSubmit(submitted)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(dismissLabel) {
                        if case .page(_, _, let vm) = mode { vm.clearPageComment() }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents(presentationDetents)
    }

    // MARK: - Paragraph Mode

    @ViewBuilder
    private func paragraphContent(preview: String) -> some View {
        ScrollView {
            Text(String(preview.prefix(300)))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.neutral)
                .lineLimit(6)
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.neutral.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.sm))
                .padding(Spacing.md)
        }
        .frame(maxHeight: 120)
        Spacer()
    }

    // MARK: - Page Mode

    @ViewBuilder
    private func pageContent(fileName: String, filePath: String, vm: MemoryViewModel) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(fileName)
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                    Text(filePath)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }

            if vm.isSubmittingPageComment {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: Spacing.xs) {
                            ProgressView()
                            Text("Agent is working\u{2026}")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.neutral)
                            ElapsedTimer()
                        }
                        Spacer()
                    }
                    .padding(.vertical, Spacing.md)
                }
            }

            if let response = vm.pageCommentResult {
                Section("Agent Response") {
                    Markdown(response)
                        .markdownTheme(.openClaw)
                        .textSelection(.enabled)
                }
            }

            if let error = vm.pageCommentError {
                Section {
                    Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private var inputPlaceholder: String {
        switch mode {
        case .paragraph: "What should change here\u{2026}"
        case .page: "What should the agent do\u{2026}"
        }
    }

    private var presentationDetents: Set<PresentationDetent> {
        switch mode {
        case .paragraph: [.medium]
        case .page: [.medium, .large]
        }
    }

    /// Cancel label changes to Done after agent completes.
    private var dismissLabel: String {
        if case .page(_, _, let vm) = mode,
           vm.pageCommentResult != nil || vm.pageCommentError != nil {
            return "Done"
        }
        return "Cancel"
    }

    private func handleSubmit(_ submitted: String) {
        switch mode {
        case .paragraph(_, let onSubmit):
            onSubmit(submitted)
            dismiss()
        case .page(_, let filePath, let vm):
            text = ""
            Task { await vm.submitPageComment(path: filePath, instruction: submitted) }
        }
    }
}
