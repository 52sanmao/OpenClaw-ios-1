import SwiftUI

struct CronDetailView: View {
    @State var vm: CronDetailViewModel
    let repository: CronDetailRepository
    @State private var expandedRunId: String?
    @State private var showRunConfirmation = false
    @State private var showDisableConfirmation = false
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
                LabeledContent("Next Run") {
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
                if vm.job.consecutiveErrors > 0 {
                    LabeledContent("Consecutive Errors") {
                        Text("\(vm.job.consecutiveErrors)")
                            .foregroundStyle(AppColors.danger)
                            .fontWeight(.semibold)
                    }
                }
            }

            // MARK: - Error + Investigate
            if let error = vm.job.lastError {
                Section("Error") {
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
                            Text("Investigate with AI")
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
                                Text("Last investigated \(prev.investigatedAtFormatted)")
                                    .font(AppTypography.micro)
                                    .underline()
                            }
                            .foregroundStyle(AppColors.primaryAction)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // MARK: - Run Stats
            if let stats = vm.stats {
                CronStatsSection(stats: stats)
            }

            // MARK: - Run History
            Section {
                if vm.isLoading && vm.runs.isEmpty {
                    CardLoadingView(minHeight: 60)
                } else if vm.runs.isEmpty && !vm.isLoading {
                    ContentUnavailableView(
                        "No Runs Yet",
                        systemImage: "clock",
                        description: Text("This job hasn't recorded any runs.")
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
                                    Text("Load More")
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
                    Text("Run History")
                    if let total = vm.totalRuns {
                        Text("(\(total) total)")
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
        .alert("Run Manually?", isPresented: $showRunConfirmation) {
            Button("Run", role: .destructive) {
                Task { await vm.triggerRun() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will trigger \"\(vm.job.name)\" immediately outside its normal schedule.")
        }
        .alert(
            vm.job.enabled ? "Disable Job?" : "Enable Job?",
            isPresented: $showDisableConfirmation
        ) {
            Button(vm.job.enabled ? "Disable" : "Enable", role: vm.job.enabled ? .destructive : nil) {
                let wasEnabled = vm.job.enabled
                Task {
                    await vm.toggleEnabled()
                    if wasEnabled { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(vm.job.enabled
                 ? "This will stop \"\(vm.job.name)\" from running on its schedule until re-enabled."
                 : "This will resume \"\(vm.job.name)\" on its normal schedule.")
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
}
