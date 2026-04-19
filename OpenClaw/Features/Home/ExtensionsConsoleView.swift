import SwiftUI

/// 扩展控制台 — 对齐 Web：wasm_tool / mcp_server / acp_agent 的安装与管理。
/// 频道（wasm_channel / channel_relay）在单独的「频道」页处理，本页不重复。
struct ExtensionsConsoleView: View {
    let vm: ToolsConfigViewModel
    let adminVM: AdminViewModel

    @State private var installingName: String?
    @State private var removingName: String?
    @State private var actionError: String?
    @State private var searchText: String = ""

    private var installedTools: [ExtensionInfoDTO] {
        adminVM.installedExtensions.filter { ext in
            let k = ext.kind.lowercased()
            return k == "wasm_tool" || k == "mcp_server" || k == "acp_agent"
        }
    }

    private var availableEntries: [ExtensionRegistryEntryDTO] {
        adminVM.extensionsRegistry.filter { entry in
            let k = entry.kind.lowercased()
            let isRelevant = k == "wasm_tool" || k == "mcp_server" || k == "acp_agent"
            guard isRelevant && entry.installed != true else { return false }
            if searchText.isEmpty { return true }
            let q = searchText.lowercased()
            if entry.name.lowercased().contains(q) { return true }
            if (entry.displayName ?? "").lowercased().contains(q) { return true }
            if (entry.description ?? "").lowercased().contains(q) { return true }
            if (entry.keywords ?? []).contains(where: { $0.lowercased().contains(q) }) { return true }
            return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                summaryStrip
                if !installedTools.isEmpty {
                    installedSection
                }
                registrySection
                if installedTools.isEmpty && availableEntries.isEmpty && !adminVM.isLoading {
                    ContentUnavailableView(
                        "暂无扩展",
                        systemImage: "puzzlepiece.extension",
                        description: Text("下拉刷新或检查 /api/extensions 与 /api/extensions/registry。")
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
                DetailTitleView(title: "扩展") {
                    Text(subtitle)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .refreshable {
            await adminVM.load()
            await vm.load()
            Haptics.shared.refreshComplete()
        }
        .task {
            if adminVM.installedExtensions.isEmpty && !adminVM.isLoading { await adminVM.load() }
            if vm.config == nil && !vm.isLoading { await vm.load() }
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
        "\(installedTools.count) 已装 · \(availableEntries.count) 可装 · \(adminVM.installedExtensions.filter { $0.kind.lowercased() == "mcp_server" }.count) MCP"
    }

    // MARK: - Summary strip

    @ViewBuilder
    private var summaryStrip: some View {
        HStack(spacing: Spacing.sm) {
            summaryTile(
                icon: "wrench.adjustable.fill",
                value: "\(installedTools.filter { $0.kind.lowercased() == "wasm_tool" }.count)",
                label: "工具",
                tint: AppColors.metricWarm
            )
            summaryTile(
                icon: "server.rack",
                value: "\(installedTools.filter { $0.kind.lowercased() == "mcp_server" }.count)",
                label: "MCP",
                tint: AppColors.metricHighlight
            )
            summaryTile(
                icon: "person.crop.rectangle.badge.plus",
                value: "\(installedTools.filter { $0.kind.lowercased() == "acp_agent" }.count)",
                label: "代理",
                tint: AppColors.metricTertiary
            )
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
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(AppColors.success)
                Text("已安装")
                    .font(AppTypography.captionBold)
                Spacer()
                Text("\(installedTools.count) 项")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            VStack(spacing: Spacing.sm) {
                ForEach(installedTools, id: \.name) { ext in
                    installedRow(ext)
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
    private func installedRow(_ ext: ExtensionInfoDTO) -> some View {
        let kindColor = color(forKind: ext.kind)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .fill(kindColor.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon(forKind: ext.kind))
                        .foregroundStyle(kindColor)
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
                    kindBadge(ext.kind)
                    if let desc = ext.description, !desc.isEmpty {
                        Text(desc)
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                            .lineLimit(2)
                    }
                }
                Spacer()
                stateBadge(ext)
            }

            if let tools = ext.tools, !tools.isEmpty {
                FlowChipsLayout(spacing: Spacing.xxs) {
                    ForEach(tools, id: \.self) { name in
                        Text(name)
                            .font(AppTypography.nano)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(kindColor.opacity(0.10)))
                            .foregroundStyle(kindColor)
                    }
                }
            }

            HStack {
                Button(role: .destructive) {
                    Task { await remove(ext.name) }
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

    // MARK: - Registry (available)

    @ViewBuilder
    private var registrySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundStyle(AppColors.metricHighlight)
                Text("可安装")
                    .font(AppTypography.captionBold)
                Spacer()
                Text("\(availableEntries.count) 项")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            searchField

            if availableEntries.isEmpty {
                Text(searchText.isEmpty ? "注册表为空" : "没有匹配结果")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(availableEntries, id: \.name) { entry in
                        registryRow(entry)
                    }
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
    private var searchField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.neutral)
            TextField("搜索名称、关键字或描述", text: $searchText)
                .font(AppTypography.caption)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.neutral)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(Color(.systemGroupedBackground))
        )
    }

    @ViewBuilder
    private func registryRow(_ entry: ExtensionRegistryEntryDTO) -> some View {
        let kindColor = color(forKind: entry.kind)
        HStack(spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(kindColor.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: icon(forKind: entry.kind))
                    .foregroundStyle(kindColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.xxs) {
                    Text(entry.displayName ?? entry.name.capitalized)
                        .font(AppTypography.body)
                        .fontWeight(.medium)
                    kindBadge(entry.kind)
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
                Task { await install(entry) }
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
                .foregroundStyle(kindColor)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(Capsule().fill(kindColor.opacity(0.12)))
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

    // MARK: - Helpers

    private func color(forKind kind: String) -> Color {
        switch kind.lowercased() {
        case "wasm_tool":  return AppColors.metricWarm
        case "mcp_server": return AppColors.metricHighlight
        case "acp_agent":  return AppColors.metricTertiary
        default:           return AppColors.neutral
        }
    }

    private func icon(forKind kind: String) -> String {
        switch kind.lowercased() {
        case "wasm_tool":  return "wrench.and.screwdriver.fill"
        case "mcp_server": return "server.rack"
        case "acp_agent":  return "person.crop.rectangle.badge.plus"
        default:           return "puzzlepiece.extension.fill"
        }
    }

    @ViewBuilder
    private func kindBadge(_ kind: String) -> some View {
        let label: String = {
            switch kind.lowercased() {
            case "wasm_tool": return "Wasm Tool"
            case "mcp_server": return "MCP Server"
            case "acp_agent": return "ACP Agent"
            default: return kind
            }
        }()
        let tint = color(forKind: kind)
        Text(label)
            .font(AppTypography.nano)
            .padding(.horizontal, Spacing.xxs)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.12)))
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private func stateBadge(_ ext: ExtensionInfoDTO) -> some View {
        let (text, color): (String, Color) = {
            if ext.active { return ("Active", AppColors.success) }
            if ext.authenticated { return ("Ready", AppColors.info) }
            if ext.needsSetup == true { return ("Setup", AppColors.warning) }
            return ("Installed", AppColors.neutral)
        }()
        Text(text)
            .font(AppTypography.nano)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Actions

    private func install(_ entry: ExtensionRegistryEntryDTO) async {
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

    private func remove(_ name: String) async {
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
