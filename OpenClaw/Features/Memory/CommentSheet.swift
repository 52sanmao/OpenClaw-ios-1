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
        /// Skill comment — shows skill info + file list, agent reads SKILL.md first.
        case skill(skill: SkillFile, files: [String], vm: MemoryViewModel)
    }

    private var title: String {
        switch mode {
        case .paragraph: "批注段落"
        case .page: "整页批注"
        case .skill: "技能批注"
        }
    }

    private var agentVM: MemoryViewModel? {
        switch mode {
        case .paragraph: nil
        case .page(_, _, let vm): vm
        case .skill(_, _, let vm): vm
        }
    }

    /// Whether the agent has started or finished.
    private var agentHasActivity: Bool {
        guard let vm = agentVM else { return false }
        return vm.isSubmittingPageComment || vm.pageCommentResult != nil || vm.pageCommentError != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch mode {
                case .paragraph(let preview, _):
                    paragraphContent(preview: preview)
                case .page(let fileName, let filePath, let vm):
                    agentContent(heading: fileName, subheading: filePath, vm: vm)
                case .skill(let skill, let files, let vm):
                    agentContent(heading: skill.displayName, subheading: "skills/\(skill.id)/ \u{2014} \(files.count) 个文件", vm: vm)
                }

                if !agentHasActivity {
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
                        agentVM?.clearPageComment()
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

    // MARK: - Agent Mode (page + skill)

    @ViewBuilder
    private func agentContent(heading: String, subheading: String, vm: MemoryViewModel) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(heading)
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                    Text(subheading)
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
                            Text("代理正在处理中…")
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
                Section("代理响应") {
                    Markdown(response)
                        .markdownTheme(.openClaw)
                        .textSelection(.enabled)
                }
            }

            if let error = vm.pageCommentError {
                Section {
                    ErrorLabel(error: error)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private var inputPlaceholder: String {
        switch mode {
        case .paragraph: "写下这里要怎么改…"
        case .page: "描述你希望这页怎么改…"
        case .skill: "告诉代理如何整理这个技能…"
        }
    }

    private var presentationDetents: Set<PresentationDetent> {
        switch mode {
        case .paragraph: [.medium]
        case .page, .skill: [.medium, .large]
        }
    }

    private var dismissLabel: String {
        guard let vm = agentVM,
              vm.pageCommentResult != nil || vm.pageCommentError != nil else {
            return "取消"
        }
        return "完成"
    }

    private func handleSubmit(_ submitted: String) {
        switch mode {
        case .paragraph(_, let onSubmit):
            onSubmit(submitted)
            dismiss()
        case .page(_, let filePath, let vm):
            text = ""
            Task { await vm.submitPageComment(path: filePath, instruction: submitted) }
        case .skill(let skill, let files, let vm):
            text = ""
            Task { await vm.submitSkillComment(skill: skill, files: files, instruction: submitted) }
        }
    }
}
