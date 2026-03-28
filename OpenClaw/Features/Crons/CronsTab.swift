import SwiftUI

struct CronsTab: View {
    let vm: CronSummaryViewModel
    let detailRepository: CronDetailRepository
    let client: GatewayClientProtocol

    @State private var jobToRun: CronJob?
    @State private var isRunning = false

    private var jobs: [CronJob] { vm.data ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if !jobs.isEmpty {
                    List(jobs) { job in
                        CronJobRow(job: job, onRun: { jobToRun = job })
                            .background(
                                NavigationLink("", destination: CronDetailView(
                                    vm: CronDetailViewModel(
                                        job: job,
                                        repository: detailRepository,
                                        client: client,
                                        onJobUpdated: { await vm.refresh() }
                                    ),
                                    repository: detailRepository
                                ))
                                .opacity(0)
                            )
                    }
                    .listStyle(.insetGrouped)
                } else if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.error {
                    ContentUnavailableView(
                        "Unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(err.localizedDescription)
                    )
                } else {
                    ContentUnavailableView(
                        "No Cron Jobs",
                        systemImage: "clock.arrow.2.circlepath",
                        description: Text("No cron jobs are configured on the gateway.")
                    )
                }
            }
            .refreshable {
                await vm.refresh()
                Haptics.shared.refreshComplete()
            }
            .navigationTitle("Cron Jobs")
            .navigationBarTitleDisplayMode(.large)
            .alert("Run Manually?", isPresented: Binding(
                get: { jobToRun != nil },
                set: { if !$0 { jobToRun = nil } }
            )) {
                Button("Run", role: .destructive) {
                    guard let job = jobToRun else { return }
                    Task { await triggerRun(job) }
                }
                Button("Cancel", role: .cancel) { jobToRun = nil }
            } message: {
                if let job = jobToRun {
                    Text("This will trigger \"\(job.name)\" immediately outside its normal schedule.")
                }
            }
        }
        .task { vm.start() }
    }

    private func triggerRun(_ job: CronJob) async {
        isRunning = true
        do {
            try await detailRepository.triggerRun(jobId: job.id)
            Haptics.shared.success()
            await vm.refresh()
        } catch {
            Haptics.shared.error()
        }
        isRunning = false
    }
}

// MARK: - Row

struct CronJobRow: View {
    let job: CronJob
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

                Text(job.scheduleDescription)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.neutral)

                HStack(spacing: Spacing.sm) {
                    Label(job.lastRunFormatted, systemImage: "arrow.counterclockwise")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)

                    Label(job.nextRunFormatted, systemImage: "arrow.clockwise")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }

                if job.consecutiveErrors > 0 {
                    Label(
                        "\(job.consecutiveErrors) consecutive error\(job.consecutiveErrors == 1 ? "" : "s")",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.danger)
                }
            }

            if let onRun {
                Button {
                    onRun()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(AppTypography.actionIcon)
                        .foregroundStyle(AppColors.primaryAction)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Run \(job.name) manually")
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
