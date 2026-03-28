import MarkdownUI
import SwiftUI

struct SessionTraceView: View {
    let run: CronRun
    let repository: CronDetailRepository

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
                        Text(run.runAtAbsolute)
                            .font(AppTypography.body)
                            .fontWeight(.medium)
                        HStack(spacing: Spacing.sm) {
                            Label(run.durationFormatted, systemImage: "clock")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                            if let model = run.model {
                                Text(model)
                                    .font(AppTypography.micro)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(AppColors.pillBackground, in: Capsule())
                                    .foregroundStyle(AppColors.pillForeground)
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

// MARK: - Trace Step Row

private struct TraceStepRow: View {
    let step: TraceStep
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header — always visible
            Button(action: onTap) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: step.iconName)
                        .font(AppTypography.caption)
                        .foregroundStyle(iconColor)
                        .frame(width: 20)

                    Text(step.title)
                        .font(AppTypography.body)
                        .fontWeight(.medium)

                    Spacer()

                    if let ts = step.timestampFormatted {
                        Text(ts)
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }

                    Image(systemName: "chevron.down")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            // Preview line when collapsed
            if !isExpanded {
                previewText
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
                    .lineLimit(1)
                    .padding(.leading, 28)
            }

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Metadata pills
                    stepMetadata

                    expandedContent
                }
                .padding(.leading, 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    @ViewBuilder
    private var stepMetadata: some View {
        let pills = metadataPills
        if !pills.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(pills, id: \.label) { pill in
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: pill.icon)
                                .font(AppTypography.badgeIcon)
                            Text(pill.label)
                                .font(AppTypography.micro)
                        }
                        .foregroundStyle(pill.color)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 3)
                        .background(AppColors.tintedBackground(pill.color), in: Capsule())
                    }
                }
            }
        }
    }

    private struct MetadataPill: Sendable {
        let icon: String
        let label: String
        let color: Color
    }

    private var metadataPills: [MetadataPill] {
        var pills: [MetadataPill] = []

        if let model = step.model {
            let short = model
                .replacingOccurrences(of: "github-copilot/", with: "")
                .replacingOccurrences(of: "anthropic/", with: "")
            pills.append(MetadataPill(icon: "cpu", label: short, color: AppColors.pillForeground))
        }

        if let provider = step.provider {
            pills.append(MetadataPill(icon: "server.rack", label: provider, color: AppColors.neutral))
        }

        if let stop = step.stopReason {
            let color: Color = stop == "stop" ? AppColors.success : stop == "toolUse" ? AppColors.metricWarm : AppColors.neutral
            pills.append(MetadataPill(icon: "stop.circle", label: stop, color: color))
        }

        if let total = step.totalTokens, total > 0 {
            let input = step.inputTokens ?? 0
            let output = step.outputTokens ?? 0
            pills.append(MetadataPill(icon: "number.circle", label: "\(Formatters.tokens(input))\u{2192}\(Formatters.tokens(output)) (\(Formatters.tokens(total)))", color: AppColors.metricPrimary))
        }

        return pills
    }


    private var iconColor: Color {
        switch step.kind {
        case .systemPrompt: AppColors.neutral
        case .userPrompt:   AppColors.metricHighlight
        case .thinking:     AppColors.metricTertiary
        case .text:         AppColors.primaryAction
        case .toolCall:     AppColors.metricWarm
        case .toolResult(_, _, _, let isError):
            isError ? AppColors.danger : AppColors.success
        }
    }

    @ViewBuilder
    private var previewText: some View {
        switch step.kind {
        case .systemPrompt(let text):
            Text(text.prefix(120))
        case .userPrompt(let text):
            Text(text.prefix(120))
        case .thinking(let text):
            Text(text.prefix(120))
        case .text(let text):
            Text(text.prefix(120))
        case .toolCall(_, _, let args):
            Text(args.prefix(120))
        case .toolResult(_, _, let output, _):
            Text(output.prefix(120))
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch step.kind {
        case .systemPrompt(let text):
            Markdown(text)
                .markdownTheme(.openClaw)
                .textSelection(.enabled)

        case .userPrompt(let text):
            Markdown(text)
                .markdownTheme(.openClaw)
                .textSelection(.enabled)

        case .thinking(let text):
            Markdown(text)
                .markdownTheme(.openClaw)
                .textSelection(.enabled)

        case .text(let text):
            Markdown(text)
                .markdownTheme(.openClaw)
                .textSelection(.enabled)

        case .toolCall(_, let name, let args):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(name, systemImage: "terminal")
                    .font(AppTypography.captionBold)
                    .foregroundStyle(AppColors.metricWarm)
                Text(args)
                    .font(AppTypography.captionMono)
                    .textSelection(.enabled)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.neutral.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))
            }

        case .toolResult(_, _, let output, let isError):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(output)
                    .font(AppTypography.captionMono)
                    .foregroundStyle(isError ? AppColors.danger : .primary)
                    .textSelection(.enabled)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.neutral.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }
}

