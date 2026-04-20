import SwiftUI

struct JobsConsoleView: View {
    @State var vm: JobsViewModel
    @State private var filter: JobStateFilter = .all
    @State private var detailId: String?
    @State private var pendingAction: JobAction?
    @State private var actionError: String?
    @State private var runningActionId: String?

    private var filteredJobs: [JobDTO] {
        switch filter {
        case .all: return vm.jobs
        case .pending: return vm.jobs.filter { $0.normalizedState == "pending" }
        case .inProgress: return vm.jobs.filter { $0.normalizedState == "in_progress" }
        case .completed: return vm.jobs.filter { $0.normalizedState == "completed" }
        case .failed: return vm.jobs.filter { ["failed", "stuck", "interrupted"].contains($0.normalizedState) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                summaryStrip
                filterPicker
                jobsList
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "任务") {
                    Text(subtitle)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .refreshable {
            await vm.load()
            Haptics.shared.refreshComplete()
        }
        .task {
            if vm.jobs.isEmpty && !vm.isLoading { await vm.load() }
        }
        .sheet(item: Binding(get: { detailId.map { JobIdentifier(id: $0) } }, set: { detailId = $0?.id })) { ident in
            JobDetailSheet(jobId: ident.id, vm: vm) { detailId = nil }
        }
        .alert("确认操作", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) {
            Button(pendingAction?.confirmLabel ?? "继续") {
                guard let action = pendingAction else { return }
                pendingAction = nil
                Task { await perform(action) }
            }
            Button("取消", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(pendingAction?.message ?? "")
        }
        .alert("操作失败", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("知道了", role: .cancel) {
                actionError = nil
            }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var subtitle: String {
        if let s = vm.summary {
            return "\(s.total) 总 · 进行中 \(s.inProgress) · 完成 \(s.completed) · 失败 \(s.failed + s.stuck)"
        }
        return "异步任务"
    }

    @ViewBuilder
    private var summaryStrip: some View {
        if let s = vm.summary {
            HStack(spacing: Spacing.sm) {
                summaryTile(icon: "clock.fill", value: "\(s.pending)", label: "待处理", tint: AppColors.warning)
                summaryTile(icon: "arrow.triangle.2.circlepath", value: "\(s.inProgress)", label: "执行中", tint: AppColors.info)
                summaryTile(icon: "checkmark.seal.fill", value: "\(s.completed)", label: "已完成", tint: AppColors.success)
                summaryTile(icon: "exclamationmark.triangle.fill", value: "\(s.failed + s.stuck)", label: "异常", tint: AppColors.danger)
            }
        }
    }

    @ViewBuilder
    private func summaryTile(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(AppTypography.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(AppTypography.cardTitle)
                .foregroundStyle(tint)
            Text(label)
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    @ViewBuilder
    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(JobStateFilter.allCases) { f in
                    Button {
                        filter = f
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: f.icon)
                                .font(AppTypography.nano)
                            Text(f.label)
                                .font(AppTypography.caption)
                        }
                        .foregroundStyle(filter == f ? Color.white : AppColors.neutral)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(filter == f ? AppColors.primaryAction : AppColors.neutral.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var jobsList: some View {
        if filteredJobs.isEmpty && !vm.isLoading {
            ContentUnavailableView(
                "没有任务",
                systemImage: "tray",
                description: Text(filter == .all ? "尚未创建任何异步任务。" : "没有符合当前筛选的任务。")
            )
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(filteredJobs) { job in
                    jobCard(job)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(Color(.systemBackground))
            )
        }
    }

    @ViewBuilder
    private func jobCard(_ job: JobDTO) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                detailId = job.id
            } label: {
                jobRow(job)
            }
            .buttonStyle(.plain)

            if job.canCancel {
                HStack {
                    Spacer()
                    Button {
                        pendingAction = .cancel(job)
                    } label: {
                        Label(runningActionId == job.id ? "取消中..." : "取消任务", systemImage: "xmark.circle")
                            .font(AppTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.danger)
                    .disabled(runningActionId == job.id)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(Color(.systemGroupedBackground))
        )
    }

    @ViewBuilder
    private func jobRow(_ job: JobDTO) -> some View {
        let tint = color(forState: job.state)
        HStack(spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(tint.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: icon(forState: job.state))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title ?? job.id)
                    .font(AppTypography.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: Spacing.xxs) {
                    Text(stateLabel(job.state))
                        .font(AppTypography.nano)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(tint.opacity(0.15)))
                        .foregroundStyle(tint)
                    if let user = job.userId, !user.isEmpty {
                        Text("·  \(user)")
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                    if let created = prettyTime(job.createdAt) {
                        Text("·  \(created)")
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
                Text(job.id)
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
        }
        .padding(Spacing.sm)
    }

    private func perform(_ action: JobAction) async {
        runningActionId = action.job.id
        defer { runningActionId = nil }
        do {
            switch action {
            case .cancel(let job):
                try await vm.cancelJob(id: job.id)
            }
            await vm.load()
            Haptics.shared.refreshComplete()
        } catch {
            actionError = error.localizedDescription
            Haptics.shared.error()
        }
    }

    private func stateLabel(_ state: String?) -> String {
        switch (state ?? "").lowercased() {
        case "in_progress": return "In Progress"
        case "interrupted": return "Interrupted"
        default: return (state ?? "unknown").capitalized
        }
    }

    private func color(forState state: String?) -> Color {
        switch (state ?? "").lowercased() {
        case "completed": return AppColors.success
        case "in_progress": return AppColors.info
        case "pending": return AppColors.warning
        case "failed", "interrupted", "stuck": return AppColors.danger
        default: return AppColors.neutral
        }
    }

    private func icon(forState state: String?) -> String {
        switch (state ?? "").lowercased() {
        case "completed": return "checkmark.seal.fill"
        case "in_progress": return "arrow.triangle.2.circlepath"
        case "pending": return "clock.fill"
        case "failed": return "xmark.octagon.fill"
        case "interrupted", "stuck": return "exclamationmark.triangle.fill"
        default: return "circle.dashed"
        }
    }

    private func prettyTime(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return nil }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }

    private enum JobStateFilter: String, CaseIterable, Identifiable {
        case all, pending, inProgress, completed, failed

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "全部"
            case .pending: "待处理"
            case .inProgress: "执行中"
            case .completed: "已完成"
            case .failed: "异常"
            }
        }

        var icon: String {
            switch self {
            case .all: "tray.full"
            case .pending: "clock"
            case .inProgress: "arrow.triangle.2.circlepath"
            case .completed: "checkmark.seal"
            case .failed: "exclamationmark.triangle"
            }
        }
    }

    private struct JobIdentifier: Identifiable {
        let id: String
    }

    private enum JobAction: Identifiable {
        case cancel(JobDTO)

        var id: String {
            switch self {
            case .cancel(let job): return "cancel-\(job.id)"
            }
        }

        var job: JobDTO {
            switch self {
            case .cancel(let job): return job
            }
        }

        var confirmLabel: String {
            switch self {
            case .cancel: return "取消任务"
            }
        }

        var message: String {
            switch self {
            case .cancel(let job):
                return "确认取消任务“\(job.title ?? job.id)”吗？"
            }
        }
    }
}

private struct JobDetailSheet: View {
    let jobId: String
    @Bindable var vm: JobsViewModel
    let onClose: () -> Void

    @State private var detail: JobDetailDTO?
    @State private var loadError: String?
    @State private var isActing = false
    @State private var showRestartConfirmation = false
    @State private var actionError: String?

    var body: some View {
        NavigationStack {
            List {
                if let detail {
                    Section("基本信息") {
                        LabeledContent("ID") { Text(detail.id).font(AppTypography.captionMono).lineLimit(1).truncationMode(.middle) }
                        if let title = detail.title, !title.isEmpty { LabeledContent("标题", value: title) }
                        if let description = detail.description, !description.isEmpty { LabeledContent("说明", value: description) }
                        if let state = detail.state { LabeledContent("状态", value: stateLabel(state)) }
                        if let user = detail.userId, !user.isEmpty { LabeledContent("用户", value: user) }
                        if let kind = detail.jobKind, !kind.isEmpty { LabeledContent("类型", value: kind) }
                        if let mode = detail.jobMode, !mode.isEmpty { LabeledContent("模式", value: mode) }
                        if let c = detail.createdAt { LabeledContent("创建", value: c) }
                        if let s = detail.startedAt { LabeledContent("开始", value: s) }
                        if let completed = detail.completedAt { LabeledContent("完成", value: completed) }
                        if let elapsed = detail.elapsedSecs { LabeledContent("耗时", value: prettyDuration(elapsed)) }
                    }

                    if let browseUrl = detail.browseUrl, let url = URL(string: browseUrl) {
                        Section {
                            Link(destination: url) {
                                Label("打开工作目录", systemImage: "folder")
                            }
                        }
                    }

                    if let transitions = detail.transitions, !transitions.isEmpty {
                        Section("状态流转") {
                            ForEach(transitions) { transition in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\((transition.fromState ?? "unknown").capitalized) → \((transition.toState ?? "unknown").capitalized)")
                                        .font(AppTypography.caption)
                                    if let at = transition.at, !at.isEmpty {
                                        Text(at)
                                            .font(AppTypography.nano)
                                            .foregroundStyle(AppColors.neutral)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    if let prompt = detail.prompt, !prompt.isEmpty {
                        Section("提示词") {
                            Text(prompt).font(AppTypography.captionMono).textSelection(.enabled)
                        }
                    }
                    if let result = detail.result, !result.isEmpty {
                        Section("结果") {
                            Text(result).font(AppTypography.captionMono).textSelection(.enabled)
                        }
                    }
                    if let err = detail.error, !err.isEmpty {
                        Section("错误") {
                            Text(err).font(AppTypography.captionMono).foregroundStyle(AppColors.danger).textSelection(.enabled)
                        }
                    }
                } else if let loadError {
                    Section("加载失败") {
                        Text(loadError).foregroundStyle(AppColors.danger).textSelection(.enabled)
                    }
                } else {
                    Section {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                }
            }
            .navigationTitle("任务详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", action: onClose)
                }
                if let detail, detail.canRetry {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isActing ? "重试中..." : "重试") {
                            showRestartConfirmation = true
                        }
                        .disabled(isActing)
                    }
                }
            }
            .task {
                await loadDetail()
            }
            .alert("确认重试", isPresented: $showRestartConfirmation) {
                Button("重试") {
                    Task { await restartJob() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确认重新启动这个失败任务吗？")
            }
            .alert("操作失败", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("知道了", role: .cancel) {
                    actionError = nil
                }
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    private func loadDetail() async {
        do {
            loadError = nil
            detail = try await vm.jobDetail(id: jobId)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func restartJob() async {
        isActing = true
        defer { isActing = false }
        do {
            try await vm.restartJob(id: jobId)
            await vm.load()
            await loadDetail()
            Haptics.shared.refreshComplete()
        } catch {
            actionError = error.localizedDescription
            Haptics.shared.error()
        }
    }

    private func stateLabel(_ state: String) -> String {
        switch state.lowercased() {
        case "in_progress": return "In Progress"
        case "interrupted": return "Interrupted"
        default: return state.capitalized
        }
    }

    private func prettyDuration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)s"
    }
}
