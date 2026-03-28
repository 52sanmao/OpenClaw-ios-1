import SwiftUI

struct SessionTraceView: View {
    let run: CronRun
    let repository: CronDetailRepository
    var jobName: String?

    @State private var trace: SessionTrace?
    @State private var isLoading = false
    @State private var error: Error?
    @State private var expandedStepId: String?

    var body: some View {
        List {
            // Run summary header
            Section {
                HStack(spacing: Spacing.sm) {
                    CronStatusDot(status: run.status)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        if let jobName {
                            Text(jobName)
                                .font(AppTypography.body)
                                .fontWeight(.semibold)
                        }
                        Text(run.runAtAbsolute)
                            .font(jobName != nil ? AppTypography.caption : AppTypography.body)
                            .fontWeight(jobName != nil ? .regular : .medium)
                            .foregroundStyle(jobName != nil ? AppColors.neutral : .primary)
                        HStack(spacing: Spacing.sm) {
                            Label(run.durationFormatted, systemImage: "clock")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                            if let model = run.model {
                                ModelPill(model: model)
                            }
                        }
                    }
                    Spacer()
                }
            }

            // Trace steps
            if isLoading && trace == nil {
                Section("Execution Trace") {
                    CardLoadingView(minHeight: 100)
                }
            } else if let trace {
                Section {
                    ForEach(trace.steps) { step in
                        TraceStepRow(
                            step: step,
                            isExpanded: expandedStepId == step.id
                        ) {
                            withAnimation(.snappy(duration: 0.3)) {
                                expandedStepId = expandedStepId == step.id ? nil : step.id
                            }
                        }
                    }

                    if trace.truncated {
                        HStack {
                            Spacer()
                            Label("History truncated — older steps not shown", systemImage: "ellipsis.circle")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                            Spacer()
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                } header: {
                    HStack {
                        Text("Execution Trace")
                        Text("(\(trace.steps.count) steps)")
                            .foregroundStyle(AppColors.neutral)
                    }
                }
            } else if let error {
                Section("Execution Trace") {
                    CardErrorView(error: error)
                }
            } else if run.sessionId == nil {
                Section("Execution Trace") {
                    Text("No session data available for this run.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.neutral)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Run Trace")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTrace()
        }
    }

    private func loadTrace() async {
        guard let sessionKey = run.sessionKey ?? run.sessionId else { return }
        isLoading = true
        do {
            trace = try await repository.fetchSessionTrace(sessionKey: sessionKey, limit: 100)
            error = nil
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
