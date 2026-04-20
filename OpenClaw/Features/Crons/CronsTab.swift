import SwiftUI

struct CronsTab: View {
    let vm: CronSummaryViewModel
    let detailRepository: CronDetailRepository
    let client: GatewayClientProtocol

    @State private var selectedTab: CronTab = .jobs
    @State private var historyVM: CronHistoryViewModel?
    @State private var jobToRun: CronJob?
    @State private var pendingJobToggle: PendingJobToggle?
    @State private var triggerError: Error?
    @State private var updatingJobIDs: Set<String> = []
    @State private var summary: RoutinesSummaryDTO?
    @State private var filter: RoutineListFilter = .all
    @State private var historyFilter: HistoryRunFilter = .all
    @State private var searchText = ""

    private var jobs: [CronJob] { vm.data ?? [] }

    private var filteredJobs: [CronJob] {
        jobs.filter { job in
            let matchesFilter = switch filter {
            case .all:
                true
            case .enabled:
                job.enabled
            case .disabled:
                !job.enabled
            case .failing:
                job.status == .failed || job.consecutiveErrors > 0
            }

            guard matchesFilter else { return false }
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
            let query = searchText.lowercased()
            return job.name.lowercased().contains(query)
                || (job.taskDescription?.lowercased().contains(query) ?? false)
                || job.scheduleDescription.lowercased().contains(query)
        }
    }


    private var filteredHistoryRuns: [CronRun] {
        guard let historyVM else { return [] }
        return historyVM.runs.filter { run in
            let matchesFilter = switch historyFilter {
            case .all:
                true
            case .succeeded:
                run.status == .succeeded
            case .failed:
                run.status == .failed
            }

            guard matchesFilter else { return false }
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }

            let query = searchText.lowercased()
            let jobName = jobNameMap[run.jobId]?.lowercased() ?? ""
            let summary = run.summary?.lowercased() ?? ""
            let model = run.model?.lowercased() ?? ""
            return jobName.contains(query)
                || run.jobId.lowercased().contains(query)
                || summary.contains(query)
                || model.contains(query)
        }
    }

    private var historyCounts: (total: Int, succeeded: Int, failed: Int) {
        guard let historyVM else { return (0, 0, 0) }
        let succeeded = historyVM.runs.filter { $0.status == .succeeded }.count
        let failed = historyVM.runs.filter { $0.status == .failed }.count
        return (historyVM.runs.count, succeeded, failed)
    }

    private var jobNameMap: [String: String] {
        Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0.name) })
    }

    enum CronTab: String, CaseIterable {
        case jobs = "定时任务"
        case history = "历史"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("视图", selection: $selectedTab) {
                    ForEach(CronTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)

                if selectedTab == .jobs {
                    filterPicker
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.xs)
                } else {
                    historyFilterPicker
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.xs)
                }

                switch selectedTab {
                case .jobs:
                    jobsList
                case .history:
                    historyList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    DetailTitleView(title: "定时任务") {
                        cronSubtitle
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        ScheduleTimelineView(jobs: jobs)
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
            }
            .searchable(text: $searchText, prompt: selectedTab == .jobs ? "搜索任务名、用途、频率" : "搜索")
            .alert("手动运行？", isPresented: Binding(
                get: { jobToRun != nil },
                set: { if !$0 { jobToRun = nil } }
            )) {
                Button("运行", role: .destructive) {
                    guard let job = jobToRun else { return }
                    Task { await triggerRun(job) }
                }
                Button("取消", role: .cancel) { jobToRun = nil }
            } message: {
                if let job = jobToRun {
                    Text("这将立即在正常计划之外触发 \"\(job.name)\"。")
                }
            }
        }
        .alert("启停任务？", isPresented: Binding(
            get: { pendingJobToggle != nil },
            set: { if !$0 { pendingJobToggle = nil } }
        )) {
            Button(toggleConfirmationTitle, role: pendingJobToggle?.enabled == false ? .destructive : nil) {
                guard let toggle = pendingJobToggle else { return }
                pendingJobToggle = nil
                Task { await setJobEnabled(toggle.job, enabled: toggle.enabled) }
            }
            Button("取消", role: .cancel) { pendingJobToggle = nil }
        } message: {
            if let toggle = pendingJobToggle {
                Text(toggleConfirmationMessage(for: toggle))
            }
        }
        .alert("运行失败", isPresented: Binding(
            get: { triggerError != nil },
            set: { if !$0 { triggerError = nil } }
        )) {
            Button("确定") { triggerError = nil }
        } message: {
            if let err = triggerError {
                Text(err.localizedDescription)
            }
        }
        .task {
            vm.start()
            await loadSummary()
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .history, historyVM == nil {
                let hvm = CronHistoryViewModel(
                    repository: detailRepository,
                    jobsProvider: { [vm] in vm.data ?? [] }
                )
                historyVM = hvm
                Task { await hvm.loadRuns() }
            }
        }
    }

    @ViewBuilder
    private var cronSubtitle: some View {
        if let summary {
            HStack(spacing: Spacing.xs) {
                Text("\(summary.total) 个任务")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
                if summary.failing > 0 {
                    Text("· \(summary.failing) 个失败")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.danger)
                }
                if summary.unverified > 0 {
                    Text("· \(summary.unverified) 个未验证")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.warning)
                }
            }
        } else if !jobs.isEmpty {
            let failed = jobs.filter { $0.status == .failed }.count
            HStack(spacing: Spacing.xs) {
                Text("\(jobs.count) 个任务")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
                if failed > 0 {
                    Text("· \(failed) 个失败")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.danger)
                }
            }
        }
    }

    @ViewBuilder
    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(RoutineListFilter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: item.icon)
                                .font(AppTypography.nano)
                            Text(item.label)
                                .font(AppTypography.caption)
                        }
                        .foregroundStyle(filter == item ? Color.white : AppColors.neutral)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(filter == item ? AppColors.primaryAction : AppColors.neutral.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }


    @ViewBuilder
    private var historyFilterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(HistoryRunFilter.allCases) { item in
                    Button {
                        historyFilter = item
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: item.icon)
                                .font(AppTypography.nano)
                            Text(item.label)
                                .font(AppTypography.caption)
                        }
                        .foregroundStyle(historyFilter == item ? Color.white : AppColors.neutral)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(historyFilter == item ? AppColors.primaryAction : AppColors.neutral.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var jobsList: some View {
        if !jobs.isEmpty {
            List {
                if let s = summary {
                    Section {
                        routinesSummaryRow(s)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .listRowBackground(Color.clear)
                    }
                }
                Section("定时任务") {
                    if filteredJobs.isEmpty {
                        ContentUnavailableView(
                            "没有匹配项",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("当前筛选下没有符合条件的自动化任务。")
                        )
                        .frame(minHeight: 120)
                    } else {
                        ForEach(filteredJobs) { job in
                            CronJobRow(
                                job: job,
                                isUpdating: updatingJobIDs.contains(job.id),
                                onToggleEnabled: { newValue in
                                    pendingJobToggle = PendingJobToggle(job: job, enabled: newValue)
                                },
                                onRun: { jobToRun = job }
                            )
                            .background(
                                NavigationLink("", destination: CronDetailView(
                                    vm: CronDetailViewModel(
                                        job: job,
                                        repository: detailRepository,
                                        client: client,
                                        store: InvestigationStore(),
                                        onJobUpdated: {
                                            await vm.refresh()
                                            await loadSummary()
                                        }
                                    ),
                                    repository: detailRepository
                                ))
                                .opacity(0)
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                async let r: Void = vm.refresh()
                async let s: Void = loadSummary()
                _ = await (r, s)
                Haptics.shared.refreshComplete()
            }
        } else if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.error {
            ContentUnavailableView(
                "不可用",
                systemImage: "wifi.exclamationmark",
                description: Text(err.localizedDescription)
            )
        } else {
            ContentUnavailableView(
                "没有定时任务",
                systemImage: "clock.arrow.2.circlepath",
                description: Text("IronClaw 服务上未配置任何定时任务。")
            )
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if let hvm = historyVM {
            if hvm.isLoading && hvm.runs.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hvm.runs.isEmpty && !hvm.isLoading {
                ContentUnavailableView(
                    "没有历史",
                    systemImage: "clock",
                    description: Text("尚未记录任何运行。")
                )
            } else if let err = hvm.error, hvm.runs.isEmpty {
                ContentUnavailableView(
                    "不可用",
                    systemImage: "wifi.exclamationmark",
                    description: Text(err.localizedDescription)
                )
            } else {
                List {
                    Section {
                        historySummaryRow
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .listRowBackground(Color.clear)
                    }

                    Section("运行历史") {
                        if filteredHistoryRuns.isEmpty {
                            ContentUnavailableView(
                                "没有匹配项",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("当前筛选下没有符合条件的执行记录。")
                            )
                            .frame(minHeight: 120)
                        } else {
                            ForEach(filteredHistoryRuns) { run in
                                CronHistoryRow(run: run, jobName: jobNameMap[run.jobId])
                                    .background(
                                        Group {
                                            if run.sessionKey != nil || run.sessionId != nil {
                                                NavigationLink("", destination: SessionTraceView(run: run, repository: detailRepository, jobName: jobNameMap[run.jobId], client: client))
                                                    .opacity(0)
                                            }
                                        }
                                    )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await hvm.loadRuns()
                    Haptics.shared.refreshComplete()
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }


    @ViewBuilder
    private var historySummaryRow: some View {
        let counts = historyCounts
        HStack(spacing: Spacing.sm) {
            summaryTile(icon: "clock.fill", value: "\(counts.total)", label: "总计", tint: AppColors.metricPrimary)
            summaryTile(icon: "checkmark.seal.fill", value: "\(counts.succeeded)", label: "成功", tint: AppColors.success)
            summaryTile(icon: "xmark.octagon.fill", value: "\(counts.failed)", label: "失败", tint: AppColors.danger)
        }
    }

    private func triggerRun(_ job: CronJob) async {
        do {
            try await detailRepository.triggerRun(jobId: job.id)
            Haptics.shared.success()
            async let r: Void = vm.refresh()
            async let s: Void = loadSummary()
            _ = await (r, s)
        } catch {
            triggerError = error
            Haptics.shared.error()
        }
    }

    private func setJobEnabled(_ job: CronJob, enabled: Bool) async {
        guard !updatingJobIDs.contains(job.id) else { return }
        updatingJobIDs.insert(job.id)
        defer { updatingJobIDs.remove(job.id) }

        do {
            try await detailRepository.setEnabled(jobId: job.id, enabled: enabled)
            async let r: Void = vm.refresh()
            async let s: Void = loadSummary()
            _ = await (r, s)
            Haptics.shared.success()
        } catch {
            triggerError = error
            Haptics.shared.error()
        }
    }

    private var toggleConfirmationTitle: String {
        pendingJobToggle?.enabled == true ? "启用" : "停用"
    }

    private func toggleConfirmationMessage(for toggle: PendingJobToggle) -> String {
        if toggle.enabled {
            return "这会重新启用“\(toggle.job.name)”并恢复按计划执行。"
        }
        return "这会停用“\(toggle.job.name)”，后续不会再按计划自动运行。"
    }

    private func loadSummary() async {
        if let s: RoutinesSummaryDTO = try? await client.stats("api/routines/summary") {
            summary = s
        }
    }

    @ViewBuilder
    private func routinesSummaryRow(_ s: RoutinesSummaryDTO) -> some View {
        HStack(spacing: Spacing.sm) {
            summaryTile(icon: "bolt.fill", value: "\(s.enabled)", label: "启用", tint: AppColors.success)
            summaryTile(icon: "pause.circle", value: "\(s.disabled)", label: "禁用", tint: AppColors.neutral)
            summaryTile(icon: "questionmark.circle", value: "\(s.unverified)", label: "未验证", tint: AppColors.warning)
            summaryTile(icon: "exclamationmark.triangle.fill", value: "\(s.failing)", label: "失败", tint: AppColors.danger)
            summaryTile(icon: "gauge.with.dots.needle.67percent", value: "\(s.runsToday)", label: "今日", tint: AppColors.metricPrimary)
        }
    }

    @ViewBuilder
    private func summaryTile(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(AppTypography.nano)
                .foregroundStyle(tint)
            Text(value)
                .font(AppTypography.captionBold)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(tint.opacity(0.08))
        )
    }
}

private struct PendingJobToggle {
    let job: CronJob
    let enabled: Bool
}


private enum RoutineListFilter: String, CaseIterable, Identifiable {
    case all, enabled, disabled, failing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "全部"
        case .enabled: "启用"
        case .disabled: "禁用"
        case .failing: "失败"
        }
    }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .enabled: "play.circle"
        case .disabled: "pause.circle"
        case .failing: "exclamationmark.triangle"
        }
    }
}

private enum HistoryRunFilter: String, CaseIterable, Identifiable {
    case all, succeeded, failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "全部"
        case .succeeded: "成功"
        case .failed: "失败"
        }
    }

    var icon: String {
        switch self {
        case .all: "clock.arrow.circlepath"
        case .succeeded: "checkmark.seal"
        case .failed: "xmark.octagon"
        }
    }
}

struct CronJobRow: View {
    let job: CronJob
    let isUpdating: Bool
    var onToggleEnabled: ((Bool) -> Void)? = nil
    var onRun: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs + 1) {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(job.enabled ? AppColors.success : AppColors.neutral)
                        .frame(width: 8, height: 8)

                    Text(job.name)
                        .font(AppTypography.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer(minLength: Spacing.xxs)

                    CronStatusBadge(status: job.status, style: .small)
                }

                if let taskDescription = job.taskDescription, !taskDescription.isEmpty {
                    Text(taskDescription)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.neutral)
                        .lineLimit(2)
                }

                HStack(spacing: Spacing.xs) {
                    Text(job.scheduleDescription)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.neutral)
                    Text("·")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.neutral)
                    Text(job.scheduleKind.capitalized)
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.primaryAction)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(AppColors.primaryAction.opacity(0.12)))
                }

                HStack(spacing: Spacing.sm) {
                    Label(job.lastRunFormatted, systemImage: "arrow.counterclockwise")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)

                    Label(job.nextRunFormatted, systemImage: "arrow.clockwise")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }

                if let model = job.configuredModel, !model.isEmpty {
                    ModelPill(model: model)
                }

                if job.consecutiveErrors > 0 {
                    Label(
                        "\(job.consecutiveErrors) 个连续错误",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.danger)
                }
            }

            VStack(alignment: .trailing, spacing: Spacing.sm) {
                if let onToggleEnabled {
                    Toggle("", isOn: Binding(
                        get: { job.enabled },
                        set: { onToggleEnabled($0) }
                    ))
                    .labelsHidden()
                    .disabled(isUpdating)
                    .tint(AppColors.primaryAction)
                    .accessibilityLabel(job.enabled ? "停用 \(job.name)" : "启用 \(job.name)")
                }

                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else if let onRun {
                    Button {
                        onRun()
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(AppTypography.actionIcon)
                            .foregroundStyle(AppColors.primaryAction)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("手动运行 \(job.name)")
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
