import SwiftUI

/// 记忆管理视图 — 展示和管理上下文记忆文件
struct MemoryListView: View {
    @Bindable var vm: MemoryViewModel
    @State private var searchText = ""
    @State private var isSearching = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                searchBar

                if vm.isLoadingFiles {
                    ProgressView("加载记忆中…")
                        .padding(.top, Spacing.xl)
                } else if !searchText.isEmpty && !vm.searchResults.isEmpty {
                    searchResultsList
                } else if !searchText.isEmpty && vm.isSearching {
                    ProgressView("搜索中…")
                        .padding(.top, Spacing.xl)
                } else if !searchText.isEmpty && vm.searchResults.isEmpty && !vm.isSearching {
                    ContentUnavailableView(
                        "无搜索结果",
                        systemImage: "magnifyingglass",
                        description: Text("未找到与「\(searchText)」相关的记忆内容。")
                    )
                } else if vm.files.isEmpty {
                    ContentUnavailableView(
                        "暂无记忆",
                        systemImage: "brain.head.profile",
                        description: Text("记忆系统将自动记录重要的上下文信息。")
                    )
                } else {
                    memoryList
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "记忆") {
                    Text("\(vm.files.count) 个文件")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .refreshable {
            await vm.loadFiles()
            Haptics.shared.refreshComplete()
        }
        .task {
            if vm.files.isEmpty && !vm.isLoadingFiles {
                await vm.loadFiles()
            }
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.neutral)
            TextField("搜索记忆…", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    vm.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.neutral)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(Color(.systemBackground))
        )
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                vm.clearSearch()
            } else {
                Task { await vm.search(query: newValue) }
            }
        }
    }

    @ViewBuilder
    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.metricPrimary)
                Text("搜索结果")
                    .font(AppTypography.captionBold)
                Spacer()
                Text("\(vm.searchResults.count) 个")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            VStack(spacing: Spacing.xs) {
                ForEach(vm.searchResults) { result in
                    NavigationLink {
                        MemoryFileView(vm: vm, file: MemoryFile(path: result.path, name: result.path))
                    } label: {
                        searchResultRow(result)
                    }
                    .buttonStyle(.plain)
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
    private func searchResultRow(_ result: MemorySearchResultDTO) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "doc.text")
                    .foregroundStyle(AppColors.metricPrimary)
                Text(result.path)
                    .font(AppTypography.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
            }
            Text(snippet(result.content, query: searchText))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.neutral)
                .lineLimit(2)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(Color(.systemGroupedBackground))
        )
    }

    @ViewBuilder
    private var memoryList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(AppColors.info)
                Text("记忆文件")
                    .font(AppTypography.captionBold)
                Spacer()
                Text("\(vm.files.count) 个")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            VStack(spacing: Spacing.xs) {
                ForEach(vm.files) { file in
                    NavigationLink {
                        MemoryFileView(vm: vm, file: file)
                    } label: {
                        memoryRow(file)
                    }
                    .buttonStyle(.plain)
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
    private func memoryRow(_ file: MemoryFile) -> some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(memoryKindTint(file.kind).opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: file.icon)
                    .foregroundStyle(memoryKindTint(file.kind))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(AppTypography.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(memoryKindLabel(file.kind))
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(Color(.systemGroupedBackground))
        )
    }

    private func memoryKindLabel(_ kind: MemoryFile.Kind) -> String {
        switch kind {
        case .bootstrap: return "根文件"
        case .dailyLog: return "日志"
        case .reference: return "参考"
        }
    }

    private func memoryKindTint(_ kind: MemoryFile.Kind) -> Color {
        switch kind {
        case .bootstrap: return AppColors.metricPrimary
        case .dailyLog: return AppColors.info
        case .reference: return AppColors.metricTertiary
        }
    }

    private func snippet(_ content: String, query: String) -> String {
        let lowerContent = content.lowercased()
        let lowerQuery = query.lowercased()
        if let range = lowerContent.range(of: lowerQuery) {
            let start = content.index(range.lowerBound, offsetBy: -40, limitedBy: content.startIndex) ?? content.startIndex
            let end = content.index(range.upperBound, offsetBy: 80, limitedBy: content.endIndex) ?? content.endIndex
            let prefix = start == content.startIndex ? "" : "…"
            let suffix = end == content.endIndex ? "" : "…"
            return prefix + String(content[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + suffix
        }
        return String(content.prefix(120))
    }
}
