import SwiftUI

/// Skills browser — lists installed skills with REST API details, search, install, and remove.
struct SkillsListView: View {
    var vm: MemoryViewModel
    @State private var searchText = ""
    @State private var showInstallSheet = false
    @State private var skillToRemove: SkillInfoDTO?

    var body: some View {
        List {
            if !vm.restSkills.isEmpty {
                installedSection
            }

            if let results = vm.skillSearchResults, !searchText.isEmpty {
                searchResultsSection(results)
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "技能") {
                    Text(vm.isLoadingRestSkills ? "加载中…" : "\(vm.restSkills.count) 个已安装")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInstallSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索技能…")
        .onSubmit(of: .search) {
            Task { await vm.searchSkills(query: searchText) }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                vm.clearSkillSearch()
            }
        }
        .refreshable {
            await vm.loadRestSkills()
            Haptics.shared.refreshComplete()
        }
        .task {
            if vm.restSkills.isEmpty && !vm.isLoadingRestSkills {
                await vm.loadRestSkills()
            }
        }
        .sheet(isPresented: $showInstallSheet) {
            SkillInstallSheet(vm: vm)
        }
        .alert("确认移除", isPresented: .init(
            get: { skillToRemove != nil },
            set: { if !$0 { skillToRemove = nil } }
        )) {
            Button("取消", role: .cancel) { skillToRemove = nil }
            Button("移除", role: .destructive) {
                if let skill = skillToRemove {
                    Task { await vm.removeSkill(name: skill.name) }
                }
            }
        } message: {
            if let skill = skillToRemove {
                Text("确定要移除技能「\(skill.name)」吗？此操作不可撤销。")
            }
        }
        .overlay {
            if vm.isLoadingRestSkills && vm.restSkills.isEmpty {
                ProgressView("加载技能…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            } else if let err = vm.restSkillsError, vm.restSkills.isEmpty {
                ContentUnavailableView(
                    "无法加载技能",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err.localizedDescription)
                )
            } else if vm.restSkills.isEmpty && !vm.isLoadingRestSkills && searchText.isEmpty {
                ContentUnavailableView(
                    "没有技能",
                    systemImage: "bolt.fill",
                    description: Text("当前未安装任何技能。点击右上角 + 安装新技能。")
                )
            }
        }
    }

    private var installedSection: some View {
        Section {
            ForEach(vm.restSkills) { skill in
                NavigationLink {
                    SkillDetailView(vm: vm, skill: SkillFile(id: skill.name, name: skill.name))
                } label: {
                    SkillInfoRow(skill: skill) {
                        skillToRemove = skill
                    }
                }
            }
        } header: {
            Text("已安装")
        } footer: {
            if !vm.restSkills.isEmpty {
                Text("点击技能可查看文件内容，左滑或点击移除按钮可卸载。")
            }
        }
    }

    @ViewBuilder
    private func searchResultsSection(_ results: SkillSearchResponseDTO) -> some View {
        if vm.isSearchingSkills {
            Section {
                ProgressView("搜索中…")
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        } else if results.catalog.isEmpty && results.installed.isEmpty {
            Section {
                Text("未找到匹配的技能")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.neutral)
                    .frame(maxWidth: .infinity)
            }
        } else {
            if !results.installed.isEmpty {
                Section("已安装匹配") {
                    ForEach(results.installed) { skill in
                        NavigationLink {
                            SkillDetailView(vm: vm, skill: SkillFile(id: skill.name, name: skill.name))
                        } label: {
                            SkillInfoRow(skill: skill) {
                                skillToRemove = skill
                            }
                        }
                    }
                }
            }

            if !results.catalog.isEmpty {
                Section {
                    ForEach(results.catalog) { entry in
                        CatalogSkillRow(entry: entry, vm: vm)
                    }
                } header: {
                    Text("ClawHub 仓库")
                } footer: {
                    if let error = results.catalogError {
                        Text("仓库搜索出错: \(error)")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.danger)
                    }
                }
            }
        }
    }
}

// MARK: - Skill Info Row

private struct SkillInfoRow: View {
    let skill: SkillInfoDTO
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(trustColor.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(trustColor)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(skill.displayName)
                    .font(AppTypography.body)
                    .fontWeight(.medium)

                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                        .lineLimit(2)
                }

                HStack(spacing: Spacing.xs) {
                    Text(skill.version)
                        .font(AppTypography.nano)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(AppColors.metricPrimary.opacity(0.10)))
                        .foregroundStyle(AppColors.metricPrimary)

                    Text(skill.trust)
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)

                    if !skill.keywords.isEmpty {
                        Text(skill.keywords.prefix(3).joined(separator: " · "))
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(AppColors.danger.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Spacing.xxs)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onRemove) {
                Label("移除", systemImage: "trash")
            }
        }
    }

    private var trustColor: Color {
        switch skill.trust.lowercased() {
        case "trusted": return AppColors.success
        case "installed": return AppColors.info
        case "unverified": return AppColors.warning
        default: return AppColors.metricTertiary
        }
    }
}

// MARK: - Catalog Skill Row

private struct CatalogSkillRow: View {
    let entry: SkillCatalogEntryDTO
    let vm: MemoryViewModel

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(entry.installed ? AppColors.success.opacity(0.14) : AppColors.metricPrimary.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: entry.installed ? "checkmark.circle.fill" : "cloud.download.fill")
                    .foregroundStyle(entry.installed ? AppColors.success : AppColors.metricPrimary)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.name)
                    .font(AppTypography.body)
                    .fontWeight(.medium)

                if !entry.description.isEmpty {
                    Text(entry.description)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                        .lineLimit(2)
                }

                HStack(spacing: Spacing.xs) {
                    if let owner = entry.owner {
                        Text(owner)
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                    if let stars = entry.stars, stars > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(AppTypography.nano)
                            Text("\(stars)")
                                .font(AppTypography.nano)
                        }
                        .foregroundStyle(AppColors.metricWarm)
                    }
                    if let downloads = entry.downloads, downloads > 0 {
                        Text("\(downloads) 下载")
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
            }

            Spacer()

            if entry.installed {
                Text("已安装")
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.success)
            } else {
                Button {
                    Task { await vm.installSkill(name: entry.name, slug: entry.slug, url: nil) }
                } label: {
                    if vm.isPerformingSkillAction {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppColors.metricPrimary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(vm.isPerformingSkillAction)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Skill Install Sheet

private struct SkillInstallSheet: View {
    var vm: MemoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("技能信息") {
                    TextField("技能名称", text: $name)
                    TextField("来源 URL（可选）", text: $url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                }

                Section {
                    Button {
                        Task {
                            await vm.installSkill(name: name, slug: nil, url: url.isEmpty ? nil : url)
                            if vm.skillActionError == nil {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isPerformingSkillAction {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("安装")
                            }
                            Spacer()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || vm.isPerformingSkillAction)
                }

                if let result = vm.skillActionResult {
                    Section {
                        Text(result)
                            .font(AppTypography.caption)
                            .foregroundStyle(vm.skillActionError == nil ? AppColors.success : AppColors.danger)
                    }
                }
            }
            .navigationTitle("安装技能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Display Name Helper

private extension SkillInfoDTO {
    var displayName: String {
        name.replacingOccurrences(of: "skill-", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
