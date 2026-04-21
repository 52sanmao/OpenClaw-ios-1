import SwiftUI

struct ThreadPickerSheet: View {
    @State var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            threadList
                .navigationTitle("选择线程")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
        }
        .task {
            await vm.loadThreads()
        }
    }

    private var threadList: some View {
        List {
            newThreadSection
            if !vm.threads.isEmpty {
                threadHistorySection
            }
        }
        .listStyle(.insetGrouped)
    }

    private var newThreadSection: some View {
        Section {
            Button {
                vm.createNewThread()
                dismiss()
            } label: {
                HStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(AppColors.success.opacity(0.14))
                            .frame(width: 36, height: 36)
                        Image(systemName: "plus")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.success)
                    }
                    Text("新对话")
                        .font(AppTypography.body)
                        .fontWeight(.medium)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var threadHistorySection: some View {
        Section("历史线程") {
            ForEach(vm.threads) { thread in
                ThreadRow(thread: thread, isActive: thread.id == vm.activeThreadId)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.switchToThread(thread)
                        dismiss()
                    }
            }
        }
    }
}

private struct ThreadRow: View {
    let thread: ChatThreadInfo
    let isActive: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            threadIcon
            threadInfo
            Spacer()
            if isActive {
                activeIndicator
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private var threadIcon: some View {
        ZStack {
            Circle()
                .fill(isActive ? AppColors.primaryAction.opacity(0.14) : AppColors.neutral.opacity(0.08))
                .frame(width: 36, height: 36)
            Image(systemName: iconName)
                .font(AppTypography.caption)
                .foregroundStyle(isActive ? AppColors.primaryAction : AppColors.neutral)
        }
    }

    private var threadInfo: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(displayTitle)
                .font(AppTypography.body)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? AppColors.primaryAction : .primary)
                .lineLimit(1)

            threadMeta
        }
    }

    private var threadMeta: some View {
        HStack(spacing: Spacing.xs) {
            if let channel = thread.channel {
                Text(channel)
                    .font(AppTypography.nano)
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(AppColors.info.opacity(0.10)))
                    .foregroundStyle(AppColors.info)
            }
            if let type = thread.threadType, type.lowercased() != "assistant" {
                Text(type)
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
            }
            if let updated = thread.updatedAt {
                Text(relativeTime(updated))
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
            }
        }
    }

    private var activeIndicator: some View {
        Image(systemName: "checkmark")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.primaryAction)
    }

    private var displayTitle: String {
        if let title = thread.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            return title
        }
        return "未命名线程"
    }

    private var iconName: String {
        switch thread.threadType?.lowercased() {
        case "agent": return "cpu"
        case "cron": return "clock"
        case "subagent": return "person.2"
        default: return "bubble.left.and.bubble.right"
        }
    }

    private func relativeTime(_ raw: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: raw) else { return raw }
        return Formatters.relativeString(for: date)
    }
}
