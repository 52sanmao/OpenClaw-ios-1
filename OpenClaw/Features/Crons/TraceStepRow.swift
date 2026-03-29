import MarkdownUI
import SwiftUI

struct TraceStepRow: View {
    let step: TraceStep
    let isExpanded: Bool
    let onTap: () -> Void
    var onComment: (() -> Void)?
    var comments: [TraceComment] = []
    var onRemoveComment: ((UUID) -> Void)?

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
            .accessibilityLabel("\(step.title), \(isExpanded ? "collapse" : "expand")")

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

                    // Inline comments
                    ForEach(comments) { comment in
                        HStack(alignment: .top, spacing: Spacing.xs) {
                            Image(systemName: "text.bubble.fill")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.metricWarm)
                            Text(comment.text)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.metricWarm)
                            Spacer()
                            if let onRemoveComment {
                                Button { onRemoveComment(comment.id) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(AppTypography.micro)
                                        .foregroundStyle(AppColors.neutral)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove comment")
                            }
                        }
                        .padding(Spacing.xs)
                        .background(AppColors.tintedBackground(AppColors.metricWarm, opacity: 0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))
                    }

                    if let onComment {
                        Button(action: onComment) {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "plus.bubble")
                                Text(comments.isEmpty ? "Add Comment" : "Add Another")
                            }
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.primaryAction)
                            .padding(.vertical, Spacing.xxs)
                        }
                        .buttonStyle(.plain)
                    }
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
                    // Model pill with provider icon (separate from metadata pills)
                    if let model = step.model {
                        ModelPill(model: model)
                    }
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
        case .systemPrompt(let text): Text(text)
        case .userPrompt(let text):   Text(text)
        case .thinking(let text):     Text(text)
        case .text(let text):         Text(text)
        case .toolCall(_, _, let args):        Text(args)
        case .toolResult(_, _, let output, _): Text(output)
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
