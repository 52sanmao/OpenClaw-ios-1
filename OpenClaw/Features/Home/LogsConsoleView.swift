import SwiftUI

struct LogsConsoleView: View {
    @State private var vm: LogsViewModel
    @State private var showFilters = false

    init(client: GatewayClientProtocol) {
        _vm = State(initialValue: LogsViewModel(client: client))
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if vm.filteredEntries.isEmpty {
                    Section {
                        ContentUnavailableView(
                            vm.isStreaming ? "等待日志…" : "日志流未启动",
                            systemImage: "text.line.last.and.arrowtriangle.forward",
                            description: Text(vm.isStreaming ? "日志条目将实时显示在此处" : "点击播放按钮开始接收日志流")
                        )
                    }
                } else {
                    ForEach(vm.filteredEntries.prefix(500)) { entry in
                        LogStreamRow(entry: entry)
                            .id(entry.id)
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "日志流") {
                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: Spacing.sm) {
                    Button { vm.togglePause() } label: {
                        Image(systemName: vm.isPaused ? "play.fill" : "pause.fill")
                            .foregroundStyle(vm.isStreaming ? AppColors.metricPrimary : AppColors.neutral)
                    }
                    .disabled(!vm.isStreaming)

                    Button { vm.isStreaming ? vm.stop() : vm.start() } label: {
                        Image(systemName: vm.isStreaming ? "stop.fill" : "play.fill")
                            .foregroundStyle(vm.isStreaming ? AppColors.danger : AppColors.success)
                    }

                    Button { vm.clear() } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(AppColors.neutral)
                    }
                    .disabled(vm.entries.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            filterBar
        }
        .onDisappear { vm.stop() }
    }

    private var statusText: String {
        if !vm.isStreaming { return "未连接" }
        if vm.isPaused { return "已暂停 · \(vm.entries.count) 条" }
        return "直播中 · \(vm.entries.count) 条"
    }

    private var statusColor: Color {
        if !vm.isStreaming { return AppColors.neutral }
        if vm.isPaused { return AppColors.warning }
        return AppColors.success
    }

    private var filterBar: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "magnifyingglass")
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                    TextField("筛选 target…", text: $vm.targetFilter)
                        .font(AppTypography.caption)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))

                Picker("", selection: $vm.levelFilter) {
                    ForEach(LogLevelFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            if !vm.levelCounts.isEmpty {
                HStack(spacing: Spacing.sm) {
                    levelChip("全部", vm.entries.count, vm.levelFilter == .all, filter: .all)
                    levelChip("调试", vm.levelCounts["debug"] ?? 0, vm.levelFilter == .debug, filter: .debug)
                    levelChip("信息", vm.levelCounts["info"] ?? 0, vm.levelFilter == .info, filter: .info)
                    levelChip("警告", vm.levelCounts["warn"] ?? 0, vm.levelFilter == .warn, filter: .warn)
                    levelChip("错误", vm.levelCounts["error"] ?? 0, vm.levelFilter == .error, filter: .error)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
    }

    private func levelChip(_ label: String, _ count: Int, _ isSelected: Bool, filter: LogLevelFilter) -> some View {
        Button {
            vm.levelFilter = filter
        } label: {
            HStack(spacing: 2) {
                Text(label)
                    .font(AppTypography.nano)
                Text("\(count)")
                    .font(AppTypography.nano)
            }
            .foregroundStyle(isSelected ? Color.white : AppColors.neutral)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? AppColors.metricPrimary : AppColors.neutral.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LogStreamRow: View {
    let entry: LogStreamEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.xs) {
                Text(entry.timeDisplay)
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
                    .frame(width: 52, alignment: .leading)

                Text(entry.level)
                    .font(AppTypography.nano)
                    .foregroundStyle(levelColor)
                    .frame(width: 36, alignment: .leading)

                Text(entry.target)
                    .font(AppTypography.nano)
                    .foregroundStyle(levelColor.opacity(0.8))
                    .lineLimit(1)

                Spacer()
            }

            Text(entry.message)
                .font(AppTypography.micro)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
        .listRowSeparator(.visible)
    }

    private var levelColor: Color {
        switch entry.normalizedLevel {
        case "debug": return AppColors.neutral
        case "info":  return AppColors.primaryAction
        case "warn":  return AppColors.warning
        case "error": return AppColors.danger
        default:      return AppColors.neutral
        }
    }
}
