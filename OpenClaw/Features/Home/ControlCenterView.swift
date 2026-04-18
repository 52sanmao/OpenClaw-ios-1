import SwiftUI

struct ControlCenterView: View {
    let modules: [ControlCenterModule]
    let draggingModuleID: String?
    let onDragHandlePress: ((String) -> Void)?

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    var body: some View {
        CardContainer(
            title: "控制中心",
            systemImage: "square.grid.2x2.fill",
            isStale: false,
            isLoading: false
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header

                LazyVGrid(columns: columns, spacing: Spacing.sm) {
                    ForEach(modules) { module in
                        NavigationLink {
                            module.destination
                        } label: {
                            ControlCenterTile(
                                module: module,
                                isDragging: draggingModuleID == module.id,
                                onDragHandlePress: onDragHandlePress
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                quickLinks

                HomeCardDetailHint()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("像网页控制台一样进入推理、渠道、扩展与用户管理")
                    .font(AppTypography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text("首页保留概览，每个模块直接进入对应控制面板，不再共享单一入口。")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }
            Spacer(minLength: Spacing.sm)
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Button {
                    onDragHandlePress?("settings-modules")
                } label: {
                    Image(systemName: draggingModuleID == "settings-modules" ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.circle")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.primaryAction)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("长按拖动控制中心")
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .onEnded { _ in onDragHandlePress?("settings-modules") }
                )
                Text("\(modules.count) 个模块")
                    .font(AppTypography.captionBold)
                    .foregroundStyle(AppColors.primaryAction)
                Text("控制台总览")
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule()
                    .fill(AppColors.primaryAction.opacity(0.08))
            )
        }
    }

    private var quickLinks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(modules.prefix(4)) { module in
                    NavigationLink {
                        module.destination
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: module.icon)
                                .font(AppTypography.nano)
                            Text(module.title)
                                .font(AppTypography.nano)
                                .lineLimit(1)
                        }
                        .foregroundStyle(AppColors.neutral)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            Capsule()
                                .fill(AppColors.neutral.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ControlCenterModule: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let detail: String
    let destination: AnyView
}

private struct ControlCenterTile: View {
    let module: ControlCenterModule
    let isDragging: Bool
    let onDragHandlePress: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .fill(AppColors.tintedBackground(module.tint, opacity: 0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: module.icon)
                        .font(AppTypography.caption)
                        .foregroundStyle(module.tint)
                }
                Spacer(minLength: Spacing.xs)
                Button {
                    onDragHandlePress?(module.id)
                } label: {
                    Image(systemName: isDragging ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.circle")
                        .font(AppTypography.caption)
                        .foregroundStyle(module.tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("长按拖动\(module.title)")
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .onEnded { _ in onDragHandlePress?(module.id) }
                )
            }

            HStack {
                Text(module.detail)
                    .font(AppTypography.nano)
                    .foregroundStyle(module.tint)
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppColors.tintedBackground(module.tint, opacity: 0.12))
                    )
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(module.title)
                    .font(AppTypography.captionBold)
                    .foregroundStyle(.primary)
                Text(module.subtitle)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
                    .lineLimit(2)
            }

            HStack(spacing: Spacing.xxs) {
                Text("进入")
                    .font(AppTypography.nano)
                Image(systemName: "arrow.up.right")
                    .font(AppTypography.nano)
            }
            .foregroundStyle(module.tint)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .strokeBorder(AppColors.tintedBackground(module.tint, opacity: 0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(module.title)，\(module.subtitle)，\(module.detail)")
    }
}
