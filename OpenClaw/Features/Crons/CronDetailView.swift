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
            // MARK: - Header
            Section {
                headerCard
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // MARK: - Schedule
            Section("Schedule") {
                LabeledContent("Frequency", value: vm.job.scheduleDescription)
                LabeledContent("Expression") {
                    Text(vm.job.scheduleExpr)
                        .font(AppTypography.captionMono)
                        .foregroundStyle(AppColors.neutral)
                }
                if let tz = vm.job.timeZone {
                    LabeledContent("Timezone", value: tz)
                }
            }

            // MARK: - Timing
            Section("Timing") {
                LabeledContent("Last Run") {
                    HStack(spacing: Spacing.xxs) {
                        CronStatusDot(status: vm.job.status)
                        Text(vm.job.lastRunFormatted)
                            .font(AppTypography.body)
                    }
                }
                if let error = vm.job.lastError {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(error)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.danger)

                        // Investigate button — bold, modern
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

                        // Previous investigation link
                        if let prev = vm.previousInvestigation {
                            Button {
                                showPreviousInvestigation = true
                            } label: {
                                HStack(spacing: Spacing.xxs) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(AppTypography.micro)
                                    Text("Last investigated \(prev.investigatedAtFormatted)")
                                        .font(AppTypography.micro)
                                }
                                .foregroundStyle(AppColors.neutral)
                            }
                            .buttonStyle(.plain)
                        }
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
                                    NavigationLink("", destination: SessionTraceView(run: run, repository: repository))
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
                    if !vm.runs.isEmpty {
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
        .navigationTitle(vm.job.name)
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                CronStatusBadge(status: vm.job.status)
                Spacer()
                if vm.isTogglingEnabled {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Toggle("", isOn: Binding(
                        get: { vm.job.enabled },
                        set: { _ in showDisableConfirmation = true }
                    ))
                    .labelsHidden()
                    .tint(AppColors.success)
                }
            }

            Button {
                showRunConfirmation = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    if vm.isTriggering {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text("Run Now")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
            }
            .background(AppColors.primaryAction, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            .foregroundStyle(.white)
            .disabled(vm.isTriggering)
            .alert("Run Manually?", isPresented: $showRunConfirmation) {
                Button("Run", role: .destructive) {
                    Task { await vm.triggerRun() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will trigger \"\(vm.job.name)\" immediately outside its normal schedule.")
            }
        }
        .padding(Spacing.md)
        .alert(
            vm.job.enabled ? "Disable Job?" : "Enable Job?",
            isPresented: $showDisableConfirmation
        ) {
            Button(vm.job.enabled ? "Disable" : "Enable", role: vm.job.enabled ? .destructive : nil) {
                Task {
                    await vm.toggleEnabled()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(vm.job.enabled
                 ? "\"\(vm.job.name)\" will stop running on its schedule until re-enabled."
                 : "\"\(vm.job.name)\" will resume running on its schedule.")
        }
    }
}
