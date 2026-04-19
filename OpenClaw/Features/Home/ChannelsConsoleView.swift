import SwiftUI

/// 频道控制台 — 对齐 Web UI：已安装的 wasm_channel / channel_relay 列表（显示激活/鉴权状态），
/// 可从注册表安装，可移除；不再混入推理 provider 信息。
struct ChannelsConsoleView: View {
    let adminVM: AdminViewModel

    @State private var installingName: String?
    @State private var removingName: String?
    @State private var actionError: String?
    @State private var showInstall = false

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    private var installedChannels: [ExtensionInfoDTO] {
        adminVM.installedExtensions.filter {
            let k = $0.kind.lowercased()
            return k == "wasm_channel" || k == "channel_relay"
        }
    }

    private var availableChannels: [ExtensionRegistryEntryDTO] {
        adminVM.extensionsRegistry.filter {
            let k = $0.kind.lowercased()
            return (k == "wasm_channel" || k == "channel_relay") && $0.installed != true
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                summaryStrip
                if !installedChannels.isEmpty {
                    installedSection
                }
                if !availableChannels.isEmpty {
                    availableSection
                }
                if installedChannels.isEmpty && availableChannels.isEmpty && !adminVM.isLoading {
                    ContentUnavailableView(
                        "暂无频道",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("下拉刷新或检查 /api/extensions / /api/extensions/registry。")
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "频道") {
                    Text(subtitle)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .refreshable {
            await adminVM.load()
            Haptics.shared.refreshComplete()
        }
        .task {
            if adminVM.installedExtensions.isEmpty && !adminVM.isLoading { await adminVM.load() }
        }
        .alert("操作失败", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好的", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var subtitle: String {
        let connected = installedChannels.filter { ($0.activationStatus?.lowercased() == "active") || ($0.active && $0.authenticated) }.count
        return "\(installedChannels.count) 个已安装 · \(connected) 活跃 · \(availableChannels.count) 可安装"
    }

    // MARK: - Summary

    @ViewBuilder
    private var summaryStrip: some View {
        HStack(spacing: Spacing.sm) {
            summaryTile(icon: "checkmark.seal.fill", value: "\(installedChannels.filter { $0.activationStatus?.lowercased() == "active" || ($0.active && $0.authenticated) }.count)", label: "活跃", tint: AppColors.success)
            summaryTile(icon: "tray.full.fill", value: "\(installedChannels.count)", label: "已安装", tint: AppColors.metricPrimary)
            summaryTile(icon: "plus.app.fill", value: "\(availableChannels.count)", label: "可安装", tint: AppColors.metricTertiary)
        }
    }

    @ViewBuilder
    private func summaryTile(icon: String, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(tint.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(tint)
                Text(label)
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    // MARK: - Installed

    @ViewBuilder
    private var installedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(AppColors.success)
                Text("已安装频道")
                    .font(AppTypography.captionBold)
                Spacer()
                Text("\(installedChannels.count) 个")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            VStack(spacing: Spacing.sm) {
                ForEach(installedChannels, id: \.name) { ext in
                    channelRow(ext)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    @ViewBuilder
    private func channelRow(_ ext: ExtensionInfoDTO) -> some View {
        let isActive = ext.activationStatus?.lowercased() == "active" || (ext.active && ext.authenticated)
        let tint: Color = isActive ? AppColors.success : AppColors.warning
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: channelIcon(ext.name))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Spacing.xxs) {
                        Text(ext.displayName ?? ext.name.capitalized)
                            .font(AppTypography.body)
                            .fontWeight(.medium)
                        if let v = ext.version {
                            Text("v\(v)")
                                .font(AppTypography.nano)
                                .foregroundStyle(AppColors.neutral)
                        }
                    }
                    Text(statusText(ext))
                        .font(AppTypography.nano)
                        .foregroundStyle(tint)
                }
                Spacer()
                statusBadge(isActive: isActive, authenticated: ext.authenticated)
            }

            if let err = ext.activationError, !err.isEmpty {
                Text(err)
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.danger)
                    .lineLimit(2)
            }

            HStack(spacing: Spacing.xs) {
                Button(role: .destructive) {
                    Task { await removeChannel(ext.name) }
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        if removingName == ext.name {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "trash")
                                .font(AppTypography.nano)
                        }
                        Text(removingName == ext.name ? "移除中…" : "移除")
                            .font(AppTypography.nano)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(AppColors.danger)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppColors.danger.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(removingName == ext.name)
                Spacer()
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(Color(.systemGroupedBackground))
        )
    }

    private func statusText(_ ext: ExtensionInfoDTO) -> String {
        if ext.activationStatus?.lowercased() == "active" { return "Active · 已认证" }
        if ext.authenticated { return "已认证，未激活" }
        if ext.needsSetup == true { return "需要配置" }
        return "已安装"
    }

    @ViewBuilder
    private func statusBadge(isActive: Bool, authenticated: Bool) -> some View {
        let (text, color): (String, Color) = {
            if isActive { return ("Active", AppColors.success) }
            if authenticated { return ("Configured", AppColors.info) }
            return ("Installed", AppColors.warning)
        }()
        Text(text)
            .font(AppTypography.nano)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func channelIcon(_ id: String) -> String {
        switch id.lowercased() {
        case let s where s.contains("telegram"):   return "paperplane.fill"
        case let s where s.contains("whatsapp"):   return "phone.circle.fill"
        case let s where s.contains("feishu") || s.contains("lark"): return "message.badge.fill"
        case let s where s.contains("discord"):    return "gamecontroller.fill"
        case let s where s.contains("slack"):      return "number"
        case let s where s.contains("web"):        return "globe"
        default: return "bubble.left.and.bubble.right.fill"
        }
    }

    // MARK: - Available

    @ViewBuilder
    private var availableSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.app.fill")
                    .foregroundStyle(AppColors.metricTertiary)
                Text("可安装频道")
                    .font(AppTypography.captionBold)
                Spacer()
                Text("\(availableChannels.count) 个")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            VStack(spacing: Spacing.xs) {
                ForEach(availableChannels, id: \.name) { entry in
                    availableRow(entry)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    @ViewBuilder
    private func availableRow(_ entry: ExtensionRegistryEntryDTO) -> some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(AppColors.metricTertiary.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: channelIcon(entry.name))
                    .foregroundStyle(AppColors.metricTertiary)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.xxs) {
                    Text(entry.displayName ?? entry.name.capitalized)
                        .font(AppTypography.body)
                        .fontWeight(.medium)
                    if let v = entry.version {
                        Text("v\(v)")
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
                if let desc = entry.description, !desc.isEmpty {
                    Text(desc)
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                Task { await installChannel(entry) }
            } label: {
                HStack(spacing: Spacing.xxs) {
                    if installingName == entry.name {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.down.app.fill")
                            .font(AppTypography.nano)
                    }
                    Text(installingName == entry.name ? "安装中…" : "安装")
                        .font(AppTypography.nano)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(AppColors.metricTertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppColors.metricTertiary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(installingName == entry.name)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(Color(.systemGroupedBackground))
        )
    }

    // MARK: - Actions

    private func installChannel(_ entry: ExtensionRegistryEntryDTO) async {
        installingName = entry.name
        defer { installingName = nil }
        do {
            try await adminVM.installExtension(name: entry.name, kind: entry.kind)
            Haptics.shared.success()
        } catch {
            actionError = error.localizedDescription
            Haptics.shared.error()
        }
    }

    private func removeChannel(_ name: String) async {
        removingName = name
        defer { removingName = nil }
        do {
            try await adminVM.removeExtension(name: name)
            Haptics.shared.success()
        } catch {
            actionError = error.localizedDescription
            Haptics.shared.error()
        }
    }
}
