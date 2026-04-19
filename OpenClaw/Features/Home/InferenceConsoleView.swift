import SwiftUI

/// 推理控制台 — 对齐 Web UI 的「推理」：当前选中 provider/模型 hero + 全量 provider 列表（带
/// 连接测试、列出模型），并把自定义 provider 与内置 provider 区分开来。
struct InferenceConsoleView: View {
    let adminVM: AdminViewModel

    @State private var probingProviderId: String?
    @State private var listingModelsProviderId: String?
    @State private var probeResult: ProbeResult?
    @State private var modelListResult: ListModelsResult?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                activeBackendHero
                customProvidersSection
                builtinProvidersSection
                if adminVM.providers.isEmpty && !adminVM.isLoading {
                    ContentUnavailableView(
                        "暂无推理配置",
                        systemImage: "cpu",
                        description: Text("下拉刷新或检查网关 /api/llm/providers 接口。")
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
                DetailTitleView(title: "推理") {
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
            if adminVM.providers.isEmpty && !adminVM.isLoading { await adminVM.load() }
        }
        .alert("连接测试", isPresented: Binding(
            get: { probeResult != nil },
            set: { if !$0 { probeResult = nil } }
        )) {
            Button("好的", role: .cancel) { probeResult = nil }
        } message: {
            if let r = probeResult {
                Text(r.provider.name + "：" + r.response.message)
            }
        }
        .sheet(item: $modelListResult) { result in
            ModelListSheet(provider: result.provider, models: result.models) {
                modelListResult = nil
            }
        }
    }

    private var subtitle: String {
        let activeId = adminVM.selectedBackendId ?? "default"
        let activeName = adminVM.providers.first(where: { $0.id == activeId })?.name
            ?? adminVM.customProviders.first(where: { $0.id == activeId })?.name
            ?? "未选择"
        let m = adminVM.selectedModel ?? "auto"
        return "\(activeName) · \(m)"
    }

    // MARK: - Active backend hero

    @ViewBuilder
    private var activeBackendHero: some View {
        let activeId = adminVM.selectedBackendId
        let provider = adminVM.providers.first(where: { $0.id == activeId })
            ?? adminVM.customProviders.first(where: { $0.id == activeId })
            ?? adminVM.providers.first(where: { $0.hasApiKey == true })

        if let provider {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Text("当前推理后端")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.metricPrimary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.metricPrimary.opacity(0.12)))
                    Spacer()
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(AppColors.metricPrimary)
                }

                HStack(alignment: .center, spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(AppColors.metricPrimary.opacity(0.12))
                            .frame(width: 64, height: 64)
                        ProviderIcon(provider: provider.id, size: 34)
                    }
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(provider.name)
                            .font(AppTypography.cardTitle)
                        Text(adminVM.selectedModel ?? provider.envModel ?? provider.defaultModel ?? "auto")
                            .font(AppTypography.captionMono)
                            .foregroundStyle(AppColors.neutral)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: Spacing.xs) {
                    metaChip(label: "Adapter", value: provider.adapter ?? "-")
                    metaChip(label: provider.builtin == true ? "内置" : "自定义",
                             value: provider.hasApiKey == true ? "已配置" : "待配置")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColors.metricPrimary.opacity(0.18), lineWidth: 1)
            )
        }
    }

    // MARK: - Custom providers section

    @ViewBuilder
    private var customProvidersSection: some View {
        if !adminVM.customProviders.isEmpty {
            providerSection(
                title: "自定义 Provider",
                icon: "sparkles",
                tint: AppColors.metricTertiary,
                providers: adminVM.customProviders
            )
        }
    }

    // MARK: - Builtin providers section

    @ViewBuilder
    private var builtinProvidersSection: some View {
        if !adminVM.providers.isEmpty {
            providerSection(
                title: "内置 Provider",
                icon: "shippingbox.fill",
                tint: AppColors.metricPrimary,
                providers: adminVM.providers
            )
        }
    }

    @ViewBuilder
    private func providerSection(title: String, icon: String, tint: Color, providers: [LLMProviderDTO]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(AppTypography.captionBold)
                Spacer()
                Text("\(providers.count) 个")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }
            VStack(spacing: Spacing.sm) {
                ForEach(providers, id: \.id) { p in
                    providerRow(p)
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
    private func providerRow(_ provider: LLMProviderDTO) -> some View {
        let isActive = provider.id == adminVM.selectedBackendId
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill((isActive ? AppColors.success : AppColors.neutral).opacity(0.14))
                        .frame(width: 36, height: 36)
                    ProviderIcon(provider: provider.id, size: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Spacing.xxs) {
                        Text(provider.name)
                            .font(AppTypography.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if isActive {
                            Text("使用中")
                                .font(AppTypography.nano)
                                .padding(.horizontal, Spacing.xxs)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(AppColors.success.opacity(0.15)))
                                .foregroundStyle(AppColors.success)
                        }
                        if provider.hasApiKey == true {
                            Image(systemName: "key.fill")
                                .font(AppTypography.nano)
                                .foregroundStyle(AppColors.success)
                        }
                    }
                    Text(provider.envModel ?? provider.defaultModel ?? "-")
                        .font(AppTypography.captionMono)
                        .foregroundStyle(AppColors.neutral)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let base = provider.envBaseUrl ?? provider.baseUrl, !base.isEmpty {
                        Text(base)
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
            }

            HStack(spacing: Spacing.xs) {
                actionButton(icon: "bolt.horizontal.circle", label: probingProviderId == provider.id ? "测试中…" : "测试连接", tint: AppColors.primaryAction, isLoading: probingProviderId == provider.id) {
                    Task { await runTest(provider) }
                }
                if provider.canListModels == true {
                    actionButton(icon: "list.bullet.rectangle.portrait", label: listingModelsProviderId == provider.id ? "拉取中…" : "模型清单", tint: AppColors.metricTertiary, isLoading: listingModelsProviderId == provider.id) {
                        Task { await runListModels(provider) }
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(isActive ? AppColors.success.opacity(0.05) : Color(.systemGroupedBackground))
        )
    }

    @ViewBuilder
    private func metaChip(label: String, value: String) -> some View {
        HStack(spacing: Spacing.xxs) {
            Text(label)
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
            Text(value)
                .font(AppTypography.captionMono)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 4)
        .background(Capsule().fill(AppColors.neutral.opacity(0.08)))
    }

    @ViewBuilder
    private func actionButton(icon: String, label: String, tint: Color, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: icon)
                        .font(AppTypography.nano)
                }
                Text(label)
                    .font(AppTypography.nano)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Actions

    private func runTest(_ provider: LLMProviderDTO) async {
        probingProviderId = provider.id
        let response = await adminVM.testConnection(for: provider)
        probingProviderId = nil
        probeResult = ProbeResult(provider: provider, response: response)
        if response.ok { Haptics.shared.success() } else { Haptics.shared.error() }
    }

    private func runListModels(_ provider: LLMProviderDTO) async {
        listingModelsProviderId = provider.id
        let response = await adminVM.listModels(for: provider)
        listingModelsProviderId = nil
        modelListResult = ListModelsResult(provider: provider, models: response.models)
        Haptics.shared.refreshComplete()
    }

    private struct ProbeResult {
        let provider: LLMProviderDTO
        let response: LLMTestConnectionResponse
    }

    private struct ListModelsResult: Identifiable {
        var id: String { provider.id }
        let provider: LLMProviderDTO
        let models: [String]
    }
}

// MARK: - Model list sheet

private struct ModelListSheet: View {
    let provider: LLMProviderDTO
    let models: [String]
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if models.isEmpty {
                        ContentUnavailableView(
                            "没有返回模型",
                            systemImage: "tray",
                            description: Text("该 provider 未返回模型清单。")
                        )
                    } else {
                        ForEach(models, id: \.self) { model in
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "cpu")
                                    .font(AppTypography.nano)
                                    .foregroundStyle(AppColors.metricPrimary)
                                Text(model)
                                    .font(AppTypography.captionMono)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("\(provider.name) · \(models.count) 个模型")
                }
            }
            .navigationTitle("模型清单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", action: onClose)
                }
            }
        }
    }
}
