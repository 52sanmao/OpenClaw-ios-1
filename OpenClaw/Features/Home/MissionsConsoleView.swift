import SwiftUI

struct MissionsConsoleView: View {
    @State var vm: MissionsViewModel
    @State private var detailId: String?
    @State private var pendingAction: MissionAction?
    @State private var showDetail = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                summaryStrip
                missionsList
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "任务集") {
                    Text(subtitle)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .refreshable {
            await vm.load()
            Haptics.shared.refreshComplete()
        }
        .task {
            if vm.missions.isEmpty && !vm.isLoading { await vm.load() }
        }
        .sheet(item: Binding(get: { detailId.map { MissionIdentifier(id: $0) } }, set: { detailId = $0?.id })) { ident in
            MissionDetailSheet(vm: vm, missionId: ident.id) {
                detailId = nil
            }
        }
        .alert("确认操作", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) {
            Button(pendingAction?.confirmLabel ?? "继续", role: pendingAction?.isDestructive == true ? .destructive : nil) {
                guard let action = pendingAction else { return }
                pendingAction = nil
                Task { await perform(action) }
            }
            Button("取消", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(pendingAction?.message ?? "")
        }
        .alert("操作失败", isPresented: Binding(get: { vm.actionError != nil }, set: { if !$0 { vm.actionError = nil } })) {
            Button("知道了", role: .cancel) {
                vm.actionError = nil
            }
        } message: {
            Text(vm.actionError ?? "")
        }
    }

    private var subtitle: String {
        if let s = vm.summary {
            return "\(s.total) 总 · 活跃 \(s.active) · 暂停 \(s.paused) · 完成 \(s.completed) · 失败 \(s.failed)"
        }
        return "自动化任务集"
    }

    @ViewBuilder
    private var summaryStrip: some View {
        if let s = vm.summary {
            HStack(spacing: Spacing.sm) {
                summaryTile(icon: "tray.fill", value: "\(s.total)", label: "总计", tint: AppColors.primaryText)
                summaryTile(icon: "play.fill", value: "\(s.active)", label: "活跃", tint: AppColors.success)
                summaryTile(icon: "pause.fill", value: "\(s.paused)", label: "暂停", tint: AppColors.warning)
                summaryTile(icon: "xmark.octagon.fill", value: "\(s.failed)", label: "失败", tint: AppColors.danger)
            }
        }
    }

    @ViewBuilder
    private func summaryTile(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(AppTypography.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(AppTypography.cardTitle)
                .foregroundStyle(tint)
            Text(label)
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    @ViewBuilder
    private var missionsList: some View {
        if vm.missions.isEmpty && !vm.isLoading {
            ContentUnavailableView(
                "没有任务集",
                systemImage: "tray",
                description: Text("尚未创建任何自动化任务集。")
            )
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(vm.missions) { mission in
                    missionCard(mission)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(Color(.systemBackground))
            )
        }
    }

    @ViewBuilder
    private func missionCard(_ mission: MissionDTO) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                detailId = mission.id
            } label: {
                missionRow(mission)
            }
            .buttonStyle(.plain)

            HStack(spacing: Spacing.sm) {
                Spacer()
                Button {
                    pendingAction = .fire(mission)
                } label: {
                    Label(vm.isActing ? "触发中..." : "立即执行", systemImage: "bolt.fill")
                        .font(AppTypography.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.metricPrimary)
                .disabled(vm.isActing)

                if mission.canPause {
                    Button {
                        pendingAction = .pause(mission)
                    } label: {
                        Label("暂停", systemImage: "pause.fill")
                            .font(AppTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.warning)
                    .disabled(vm.isActing)
                }

                if mission.canResume {
                    Button {
                        pendingAction = .resume(mission)
                    } label: {
                        Label("恢复", systemImage: "play.fill")
                            .font(AppTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.success)
                    .disabled(vm.isActing)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(Color(.systemGroupedBackground))
        )
    }

    @ViewBuilder
    private func missionRow(_ mission: MissionDTO) -> some View {
        let tint = color(forStatus: mission.status)
        HStack(spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(tint.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: icon(forStatus: mission.status))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(mission.name ?? mission.id)
                    .font(AppTypography.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: Spacing.xxs) {
                    Text(statusLabel(mission.status))
                        .font(AppTypography.nano)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(tint.opacity(0.15)))
                        .foregroundStyle(tint)
                    if let cadence = mission.cadenceDescription ?? mission.cadenceType, !cadence.isEmpty {
                        Text("·  \(cadence)")
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                    if let count = mission.threadCount {
                        Text("·  \(count) 线程")
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
                if let next = mission.nextFireAt, !next.isEmpty {
                    Text("下次: \(next)")
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
        }
        .padding(Spacing.sm)
    }

    private func perform(_ action: MissionAction) async {
        switch action {
        case .fire(let mission):
            await vm.fireMission(id: mission.id)
        case .pause(let mission):
            await vm.pauseMission(id: mission.id)
        case .resume(let mission):
            await vm.resumeMission(id: mission.id)
        }
    }

    private func statusLabel(_ status: String?) -> String {
        switch (status ?? "").lowercased() {
        case "active": return "活跃"
        case "paused": return "暂停"
        case "completed": return "完成"
        case "failed": return "失败"
        default: return (status ?? "未知").capitalized
        }
    }

    private func color(forStatus status: String?) -> Color {
        switch (status ?? "").lowercased() {
        case "active": return AppColors.success
        case "paused": return AppColors.warning
        case "completed": return AppColors.info
        case "failed": return AppColors.danger
        default: return AppColors.neutral
        }
    }

    private func icon(forStatus status: String?) -> String {
        switch (status ?? "").lowercased() {
        case "active": return "play.fill"
        case "paused": return "pause.fill"
        case "completed": return "checkmark.seal.fill"
        case "failed": return "xmark.octagon.fill"
        default: return "circle.dashed"
        }
    }

    private enum MissionAction: Identifiable {
        case fire(MissionDTO)
        case pause(MissionDTO)
        case resume(MissionDTO)

        var id: String {
            switch self {
            case .fire(let m): return "fire-\(m.id)"
            case .pause(let m): return "pause-\(m.id)"
            case .resume(let m): return "resume-\(m.id)"
            }
        }

        var mission: MissionDTO {
            switch self {
            case .fire(let m): return m
            case .pause(let m): return m
            case .resume(let m): return m
            }
        }

        var confirmLabel: String {
            switch self {
            case .fire: return "立即执行"
            case .pause: return "暂停"
            case .resume: return "恢复"
            }
        }

        var isDestructive: Bool {
            switch self {
            case .fire: return true
            case .pause, .resume: return false
            }
        }

        var message: String {
            switch self {
            case .fire(let m):
                return "确认立即执行任务集「\(m.name ?? m.id)」吗？这将创建一个新线程。"
            case .pause(let m):
                return "确认暂停任务集「\(m.name ?? m.id)」吗？"
            case .resume(let m):
                return "确认恢复任务集「\(m.name ?? m.id)」吗？"
            }
        }
    }
}

private struct MissionIdentifier: Identifiable {
    let id: String
}

private struct MissionDetailSheet: View {
    @Bindable var vm: MissionsViewModel
    let missionId: String
    let onClose: () -> Void

    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let mission = vm.selectedMission, mission.id == missionId {
                    ScrollView {
                        VStack(spacing: Spacing.md) {
                            header(mission)
                            metadataGrid(mission)
                            if let threads = mission.threads, !threads.isEmpty {
                                threadsSection(threads)
                            }
                        }
                        .padding(Spacing.md)
                    }
                } else if let loadError {
                    ContentUnavailableView(
                        "加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    DetailTitleView(title: vm.selectedMission?.name ?? "任务集详情") {
                        Text(statusLabel(vm.selectedMission?.status))
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", action: onClose)
                }
            }
            .task {
                await vm.loadDetail(id: missionId)
            }
        }
    }

    private func header(_ mission: MissionDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                badge(text: statusLabel(mission.status), tint: color(forStatus: mission.status))
                Spacer()
            }
            HStack(spacing: Spacing.sm) {
                if mission.canPause {
                    Button {
                        Task { await vm.pauseMission(id: mission.id) }
                    } label: {
                        Label("暂停", systemImage: "pause.fill")
                            .font(AppTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.warning)
                    .disabled(vm.isActing)
                }
                if mission.canResume {
                    Button {
                        Task { await vm.resumeMission(id: mission.id) }
                    } label: {
                        Label("恢复", systemImage: "play.fill")
                            .font(AppTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.success)
                    .disabled(vm.isActing)
                }
                Button {
                    Task { await vm.fireMission(id: mission.id) }
                } label: {
                    Label(vm.isActing ? "触发中..." : "立即执行", systemImage: "bolt.fill")
                        .font(AppTypography.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.metricPrimary)
                .disabled(vm.isActing)
                Spacer()
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }

    private func metadataGrid(_ mission: MissionDetailDTO) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
            metaTile(label: "ID", value: mission.id, monospace: true)
            metaTile(label: "状态", value: statusLabel(mission.status))
            if let cadence = mission.cadenceDescription ?? mission.cadenceType, !cadence.isEmpty {
                metaTile(label: "频率", value: cadence)
            }
            if let today = mission.threadsToday, let max = mission.maxThreadsPerDay {
                metaTile(label: "今日线程", value: "\(today) / \(max)")
            }
            if let count = mission.threadCount {
                metaTile(label: "总线程", value: "\(count)")
            }
            if let created = mission.createdAt, !created.isEmpty {
                metaTile(label: "创建", value: created)
            }
            if let next = mission.nextFireAt, !next.isEmpty {
                metaTile(label: "下次执行", value: next)
            }
        }
    }

    private func threadsSection(_ threads: [MissionThreadDTO]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("线程")
                .font(AppTypography.captionBold)
                .foregroundStyle(AppColors.primaryText)
            VStack(spacing: Spacing.sm) {
                ForEach(threads) { thread in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.xs) {
                            Text(thread.id)
                                .font(AppTypography.captionMono)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        HStack(spacing: Spacing.sm) {
                            if let type = thread.threadType, !type.isEmpty {
                                badge(text: type, tint: AppColors.metricPrimary)
                            }
                            if let steps = thread.stepCount {
                                Text("\(steps) 步")
                                    .font(AppTypography.nano)
                                    .foregroundStyle(AppColors.neutral)
                            }
                            if let tokens = thread.totalTokens {
                                Text("\(tokens) tokens")
                                    .font(AppTypography.nano)
                                    .foregroundStyle(AppColors.neutral)
                            }
                            if let cost = thread.totalCostUsd, cost > 0 {
                                Text("$\(String(format: "%.4f", cost))")
                                    .font(AppTypography.nano)
                                    .foregroundStyle(AppColors.neutral)
                            }
                            Spacer()
                        }
                    }
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: AppRadius.md))
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private func metaTile(label: String, value: String, monospace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
            Text(value)
                .font(monospace ? AppTypography.captionMono : AppTypography.caption)
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(monospace ? 2 : nil)
                .truncationMode(.middle)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(AppTypography.nano)
            .padding(.horizontal, Spacing.xxs)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }

    private func statusLabel(_ status: String?) -> String {
        switch (status ?? "").lowercased() {
        case "active": return "活跃"
        case "paused": return "暂停"
        case "completed": return "完成"
        case "failed": return "失败"
        default: return (status ?? "未知").capitalized
        }
    }

    private func color(forStatus status: String?) -> Color {
        switch (status ?? "").lowercased() {
        case "active": return AppColors.success
        case "paused": return AppColors.warning
        case "completed": return AppColors.info
        case "failed": return AppColors.danger
        default: return AppColors.neutral
        }
    }
}
