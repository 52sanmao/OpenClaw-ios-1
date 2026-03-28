import MarkdownUI
import SwiftUI

struct TraceStepRow: View {
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
                    stepMetadata
                    expandedContent
                }
                .padding(.leading, 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    // MARK: - Metadata Pills

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
            pills.append(MetadataPill(icon: "cpu", label: Formatters.modelShortName(model), color: AppColors.pillForeground))
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

    // MARK: - Colors

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

    // MARK: - Preview Text

    @ViewBuilder
    private var previewText: some View {
        switch step.kind {
        case .systemPrompt(let text): Text(text.prefix(120))
        case .userPrompt(let text):   Text(text.prefix(120))
        case .thinking(let text):     Text(text.prefix(120))
        case .text(let text):         Text(text.prefix(120))
        case .toolCall(_, _, let args):        Text(args.prefix(120))
        case .toolResult(_, _, let output, _): Text(output.prefix(120))
        }
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        switch step.kind {
        case .systemPrompt(let text), .userPrompt(let text), .thinking(let text), .text(let text):
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
