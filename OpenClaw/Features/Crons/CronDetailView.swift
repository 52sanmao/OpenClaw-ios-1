import SwiftUI

struct CronDetailView: View {
    @State var vm: CronDetailViewModel
    let repository: CronDetailRepository
    @State private var expandedRunId: String?
    @State private var showRunConfirmation = false
    @State private var showDisableConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showInvestigation = false
    @State private var showPreviousInvestigation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // MARK: - About (merged: schedule + timing + config)
            Section("关于") {
                // Task description
                if let task = vm.job.taskDescription {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("用途")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                        Text(task)
                            .font(AppTypography.caption)
                    }
                }

                // Configured model
                if let model = vm.job.configuredModel {
                    LabeledContent("模型") {
                        ModelPill(model: model)
                    }
                }

                // Schedule
                LabeledContent("频率", value: vm.job.scheduleDescription)
                LabeledContent("表达式") {
                    Text(vm.job.scheduleExpr)
                        .font(AppTypography.captionMono)
                        .foregroundStyle(AppColors.neutral)
                }
                if let tz = vm.job.timeZone {
                    LabeledContent("时区", value: tz)
                }

                // Timing
                LabeledContent("上次运行") {
                    HStack(spacing: Spacing.xxs) {
                        CronStatusDot(status: vm.job.status)
                        Text(vm.job.lastRunFormatted)
                            .font(AppTypography.body)
                    }
                }
                LabeledContent("下次运行") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(vm.job.nextRunFormatted)
                            .font(AppTypography.body)
                        if let nextRun = vm.job.nextRun {
                            Text(Formatters.absoluteString(for: nextRun))
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                        }
                    }
                }
                if let detail = vm.detail {
                    if let verification = detail.verificationStatus, !verification.isEmpty {
                        LabeledContent("验证", value: verification)
                    }
                    if let createdAt = detail.createdAt, !createdAt.isEmpty {
                        LabeledContent("创建时间", value: createdAt)
                    }
                    if let runCount = detail.runCount {
                        LabeledContent("运行次数", value: "\(runCount)")
                    }
                }
            }

            if let detail = vm.detail,
               let verification = detail.verificationStatus,
               verification.lowercased() == "unverified" {
                Section("验证") {
                    Text("该任务已创建或更新，但尚未通过一次成功运行完成验证。")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.neutral)
                }
            }

            // MARK: - Error + Investigate
            if let error = vm.job.lastError {
                Section("错误") {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)

                    Button {
                        showInvestigation = true
                        Task { await vm.investigateError() }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(AppTypography.body)
                            Text("用 AI 排查")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .foregroundStyle(.white)
                        .background(AppColors.metricTertiary, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                    }
                    .disabled(vm.isInvestigating)

                    if let prev = vm.previousInvestigation {
                        Button {
                            showPreviousInvestigation = true
                        } label: {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(AppTypography.micro)
                                Text("上次排查于 \(prev.investigatedAtFormatted)")
                                    .font(AppTypography.micro)
                                    .underline()
                            }
                            .foregroundStyle(AppColors.primaryAction)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // MARK: - Operation Errors
            if let runtimeError = vm.error {
                Section("操作错误") {
                    Text(runtimeError.localizedDescription)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)

                    Text("如果这里报错，而聊天页仍可使用，通常表示是 routines 接口本身失败，而不是整个 App 不可用。")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    Text("右下角日志浮窗会额外记录 /api/routines、/api/routines/{id}/runs、trigger、toggle、delete 的请求阶段，便于确认失败发生在列表刷新、读历史、立即运行、启停还是删除操作。")
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                }
            }

            // MARK: - Run Stats
            if let stats = vm.stats {
                CronStatsSection(stats: stats)
            }

            if let detail = vm.detail,
               let conversationId = detail.conversationId,
               !conversationId.isEmpty {
                Section("执行线程") {
                    NavigationLink {
                        SessionTraceView(
                            sessionKey: conversationId,
                            title: vm.job.name,
                            subtitle: "执行线程",
                            newestFirst: true,
                            repository: RemoteSessionRepository(client: vm.client),
                            client: vm.client
                        )
                    } label: {
                        Label("查看执行线程", systemImage: "bubble.left.and.text.bubble.right")
                    }
                }
            }

            if let detail = vm.detail,
               let trigger = detail.trigger {
                routineJSONSection(title: "触发器配置", value: trigger)
            }

            if let detail = vm.detail,
               let action = detail.action {
                routineJSONSection(title: "动作配置", value: action)
            }

            if let detail = vm.detail,
               let guardrails = detail.guardrails {
                routineJSONSection(title: "防护规则", value: guardrails)
            }

            if let detail = vm.detail,
               let notify = detail.notify {
                routineJSONSection(title: "通知配置", value: notify)
            }

            if let detail = vm.detail,
               let recentRuns = detail.recentRuns,
               !recentRuns.isEmpty {
                Section("近期执行") {
                    ForEach(recentRuns) { run in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                                Text(run.status ?? "unknown")
                                    .font(AppTypography.caption)
                                    .fontWeight(.semibold)
                                if let started = formattedRelativeTime(run.startedAt) {
                                    Text(started)
                                        .font(AppTypography.nano)
                                        .foregroundStyle(AppColors.neutral)
                                }
                                Spacer()
                                if let tokens = run.tokensUsed {
                                    Text(Formatters.tokens(tokens))
                                        .font(AppTypography.nano)
                                        .foregroundStyle(AppColors.neutral)
                                }
                            }
                            if let summary = run.resultSummary, !summary.isEmpty {
                                Text(summary)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.neutral)
                                    .lineLimit(3)
                            }
                            HStack(spacing: Spacing.xxs) {
                                if let triggerType = run.triggerType, !triggerType.isEmpty {
                                    Label(triggerType, systemImage: "bolt")
                                }
                                if let jobId = run.jobId, !jobId.isEmpty {
                                    Label(jobId, systemImage: "number")
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // MARK: - Run History
            Section {
                if vm.isLoading && vm.runs.isEmpty {
                    CardLoadingView(minHeight: 60)
                } else if vm.runs.isEmpty && !vm.isLoading {
                    ContentUnavailableView(
                        "暂无运行记录",
                        systemImage: "clock",
                        description: Text("这个任务还没有产生任何运行记录。")
                    )
                    .frame(minHeight: 100)
                } else {
                    ForEach(vm.runs) { run in
                        CronRunRow(run: run, isExpanded: expandedRunId == run.id) {
                            withAnimation(.snappy(duration: 0.3)) {
                                expandedRunId = expandedRunId == run.id ? nil : run.id
                            }
                        }
                        .background(
                            Group {
                                if run.sessionKey != nil || run.sessionId != nil {
                                    NavigationLink("", destination: SessionTraceView(run: run, repository: repository, jobName: vm.job.name, client: vm.client))
                                        .opacity(0)
                                }
                            }
                        )
                    }

                    if vm.hasMore {
                        Button {
                            Task { await vm.loadMore() }
                        } label: {
                            HStack {
                                Spacer()
                                if vm.isLoadingMore {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Text("加载更多")
                                        .font(AppTypography.body)
                                        .foregroundStyle(AppColors.primaryAction)
                                }
                                Spacer()
                            }
                            .padding(.vertical, Spacing.xs)
                        }
                        .disabled(vm.isLoadingMore)
                    }
                }
            } header: {
                HStack {
                    Text("运行历史")
                    if let total = vm.totalRuns {
                        Text("(共 \(total) 条)")
                            .foregroundStyle(AppColors.neutral)
                    } else if !vm.runs.isEmpty {
                        Text("(\(vm.runs.count))")
                            .foregroundStyle(AppColors.neutral)
                    }
                    Spacer()
                    if vm.isLoading && !vm.runs.isEmpty {
                        ProgressView().scaleEffect(0.7)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Custom title with status subtitle
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: vm.job.name) {
                    CronStatusBadge(status: vm.job.status, style: .small)
                }
            }

            // Run Now + Enable/Disable
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    if vm.isDeleting {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "trash")
                            .foregroundStyle(AppColors.danger)
                    }
                }
                .disabled(vm.isDeleting)
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: Spacing.sm) {
                    // Enable/Disable
                    Button {
                        showDisableConfirmation = true
                    } label: {
                        if vm.isTogglingEnabled {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: vm.job.enabled ? "pause.circle" : "play.circle")
                                .foregroundStyle(vm.job.enabled ? AppColors.warning : AppColors.success)
                        }
                    }

                    // Run Now
                    Button {
                        showRunConfirmation = true
                    } label: {
                        if vm.isTriggering {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "play.fill")
                                .foregroundStyle(AppColors.primaryAction)
                        }
                    }
                }
            }
        }
        .alert("立即运行？", isPresented: $showRunConfirmation) {
            Button("运行", role: .destructive) {
                Task { await vm.triggerRun() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会立刻触发“\(vm.job.name)”运行，不再等待原定计划时间。")
        }
        .alert(
            "删除任务？",
            isPresented: $showDeleteConfirmation
        ) {
            Button("删除", role: .destructive) {
                Task {
                    let deleted = await vm.deleteRoutine()
                    if deleted { dismiss() }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后，“\(vm.job.name)”及其计划将被移除。")
        }
        .alert(
            vm.job.enabled ? "禁用任务？" : "启用任务？",
            isPresented: $showDisableConfirmation
        ) {
            Button(vm.job.enabled ? "禁用" : "启用", role: vm.job.enabled ? .destructive : nil) {
                let wasEnabled = vm.job.enabled
                Task {
                    await vm.toggleEnabled()
                    if wasEnabled { dismiss() }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(vm.job.enabled
                 ? "禁用后，“\(vm.job.name)”将停止按计划自动运行，直到你重新启用它。"
                 : "启用后，“\(vm.job.name)”会恢复按正常计划运行。")
        }
        .refreshable {
            await vm.loadRuns()
            Haptics.shared.refreshComplete()
        }
        .sheet(isPresented: $showInvestigation) {
            InvestigateSheet(vm: vm)
        }
        .sheet(isPresented: $showPreviousInvestigation) {
            if let prev = vm.previousInvestigation {
                SavedInvestigationSheet(investigation: prev)
            }
        }
        .task {
            await vm.loadRuns()
        }
    }

    private func formattedRelativeTime(_ raw: String?) -> String? {
        guard let date = parseISODate(raw) else { return nil }
        return Formatters.relativeString(for: date)
    }

    private func parseISODate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    @ViewBuilder
    private func routineJSONSection(title: String, value: JSONValue) -> some View {
        Section(title) {
            Text(prettyJSONString(value))
                .font(AppTypography.captionMono)
                .textSelection(.enabled)
        }
    }

    private func prettyJSONString(_ value: JSONValue) -> String {
        func unwrap(_ value: JSONValue) -> Any {
            switch value {
            case .string(let string):
                return string
            case .int(let int):
                return int
            case .double(let double):
                return double
            case .bool(let bool):
                return bool
            case .array(let array):
                return array.map(unwrap)
            case .object(let object):
                return object.mapValues(unwrap)
            case .null:
                return NSNull()
            }
        }

        let raw = unwrap(value)
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: raw)
        }
        return string
    }
}
