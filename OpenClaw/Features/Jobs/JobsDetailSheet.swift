import SwiftUI

struct JobDetailSheet: View {
    let jobId: String
    @Bindable var vm: JobsViewModel
    let onClose: () -> Void

    @State private var detail: JobDetailDTO?
    @State private var loadError: String?
    @State private var isActing = false
    @State private var showRestartConfirmation = false
    @State private var actionError: String?
    @State private var selectedTab: JobDetailTab = .overview
    @State private var activityFilter: JobActivityFilter = .all
    @State private var events: [JobEventDTO] = []
    @State private var isLoadingEvents = false
    @State private var filesRoot: [JobFileNode] = []
    @State private var selectedFilePath: String?
    @State private var fileContent: JobFileReadResponseDTO?
    @State private var isLoadingFiles = false
    @State private var isLoadingFileContent = false
    @State private var followUpText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    VStack(spacing: 0) {
                        header(detail)
                        tabPicker
                        Divider()
                        tabContent(detail)
                    }
                    .background(Color(.systemGroupedBackground))
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
                    let titleText = detail?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    DetailTitleView(title: (titleText?.isEmpty == false ? titleText : detail?.id) ?? "任务详情") {
                        Text(detail.map { detailSubtitle($0) } ?? "加载中…")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", action: onClose)
                }
                if let detail, detail.canRetry {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isActing ? "重试中..." : "重试") {
                            showRestartConfirmation = true
                        }
                        .disabled(isActing)
                    }
                }
            }
            .task {
                await loadDetail(initial: true)
            }
            .alert("确认重试", isPresented: $showRestartConfirmation) {
                Button("重试") {
                    Task { await restartJob() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确认重新启动这个失败任务吗？")
            }
            .alert("操作失败", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("知道了", role: .cancel) {
                    actionError = nil
                }
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    private func header(_ detail: JobDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(detail.title?.isEmpty == false ? (detail.title ?? detail.id) : detail.id)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.primaryText)
                    HStack(spacing: Spacing.xs) {
                        badge(text: stateLabel(detail.state), tint: color(forState: detail.state))
                        if let kind = detail.jobKind, !kind.isEmpty {
                            badge(text: kind, tint: AppColors.metricPrimary)
                        }
                        if let mode = detail.jobMode, !mode.isEmpty {
                            badge(text: mode, tint: AppColors.metricTertiary)
                        }
                    }
                }
                Spacer()
            }

            HStack(spacing: Spacing.sm) {
                if let browseUrl = detail.browseUrl, let url = URL(string: browseUrl) {
                    Link(destination: url) {
                        Label("浏览文件", systemImage: "folder")
                            .font(AppTypography.caption)
                    }
                    .buttonStyle(.bordered)
                }
                if detail.canPrompt == true {
                    Label("支持跟进提示", systemImage: "paperplane")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
                Spacer()
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }

    private var tabPicker: some View {
        Picker("任务详情", selection: $selectedTab) {
            ForEach(JobDetailTab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func tabContent(_ detail: JobDetailDTO) -> some View {
        switch selectedTab {
        case .overview:
            overviewTab(detail)
        case .activity:
            activityTab(detail)
                .task(id: detail.id) {
                    await loadEventsIfNeeded(force: false)
                }
        case .files:
            filesTab(detail)
                .task(id: detail.id) {
                    await loadFilesIfNeeded(force: false)
                }
        }
    }

    private func overviewTab(_ detail: JobDetailDTO) -> some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                metadataGrid(detail)
                if let description = detail.description, !description.isEmpty {
                    infoCard(title: "说明") {
                        Text(description)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                if let transitions = detail.transitions, !transitions.isEmpty {
                    infoCard(title: "状态流转") {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            ForEach(transitions) { transition in
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    HStack(spacing: Spacing.xs) {
                                        badge(text: stateLabel(transition.from), tint: color(forState: transition.from))
                                        Image(systemName: "arrow.right")
                                            .font(AppTypography.nano)
                                            .foregroundStyle(AppColors.neutral)
                                        badge(text: stateLabel(transition.to), tint: color(forState: transition.to))
                                        Spacer()
                                    }
                                    if let timestamp = transition.timestamp, !timestamp.isEmpty {
                                        Text(timestamp)
                                            .font(AppTypography.micro)
                                            .foregroundStyle(AppColors.neutral)
                                    }
                                    if let reason = transition.reason, !reason.isEmpty {
                                        Text(reason)
                                            .font(AppTypography.caption)
                                            .foregroundStyle(AppColors.neutral)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                if let result = detail.result, !result.isEmpty {
                    infoCard(title: "结果") {
                        Text(result)
                            .font(AppTypography.captionMono)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                if let error = detail.error, !error.isEmpty {
                    infoCard(title: "错误") {
                        Text(error)
                            .font(AppTypography.captionMono)
                            .foregroundStyle(AppColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(Spacing.md)
        }
    }

    private func metadataGrid(_ detail: JobDetailDTO) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
            metaTile(label: "ID", value: detail.id, monospace: true)
            metaTile(label: "状态", value: stateLabel(detail.state))
            metaTile(label: "创建", value: detail.createdAt ?? "-")
            metaTile(label: "开始", value: detail.startedAt ?? "-")
            metaTile(label: "完成", value: detail.completedAt ?? "-")
            metaTile(label: "耗时", value: detail.elapsedSecs.map(prettyDuration) ?? "-")
            if let user = detail.userId, !user.isEmpty {
                metaTile(label: "用户", value: user)
            }
            if let kind = detail.jobKind, !kind.isEmpty {
                metaTile(label: "类型", value: kind)
            }
            if let mode = detail.jobMode, !mode.isEmpty {
                metaTile(label: "模式", value: mode)
            }
        }
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

    private func activityTab(_ detail: JobDetailDTO) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(JobActivityFilter.allCases, id: \.self) { filter in
                            Button {
                                activityFilter = filter
                            } label: {
                                Text(filter.title)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(activityFilter == filter ? Color.white : AppColors.neutral)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(activityFilter == filter ? AppColors.primaryAction : AppColors.neutral.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
                if isLoadingEvents {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .padding(Spacing.md)
            .background(Color(.systemBackground))

            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    isLoadingEvents ? "正在载入活动" : "暂无活动",
                    systemImage: "waveform.path.ecg",
                    description: Text(isLoadingEvents ? "正在同步任务事件流。" : "这个任务还没有可展示的活动事件。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: Spacing.sm) {
                        ForEach(filteredEvents, id: \.stableId) { event in
                            activityEventCard(event)
                        }
                    }
                    .padding(Spacing.md)
                }
            }

            if detail.canPrompt == true {
                followUpBar
            }
        }
    }

    private var filteredEvents: [JobEventDTO] {
        switch activityFilter {
        case .all:
            return events
        case .message:
            return events.filter { $0.eventType == "message" }
        case .toolUse:
            return events.filter { $0.eventType == "tool_use" }
        case .toolResult:
            return events.filter { $0.eventType == "tool_result" }
        case .status:
            return events.filter { ["status", "result"].contains($0.eventType) }
        }
    }

    private func activityEventCard(_ event: JobEventDTO) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                badge(text: eventTitle(event.eventType), tint: eventTint(event.eventType))
                if let createdAt = event.createdAt, !createdAt.isEmpty {
                    Text(createdAt)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
                Spacer()
            }

            if let summary = activitySummary(for: event), !summary.isEmpty {
                Text(summary)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.primaryText)
            }

            if let payload = prettyJSON(event.data), !payload.isEmpty {
                Text(payload)
                    .font(AppTypography.captionMono)
                    .foregroundStyle(AppColors.neutral)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    private var followUpBar: some View {
        VStack(spacing: Spacing.xs) {
            Divider()
            HStack(spacing: Spacing.sm) {
                TextField("发送后续提示…", text: $followUpText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button("发送") {
                    Task { await sendPrompt(done: false) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isActing || followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("完成") {
                    Task { await sendPrompt(done: true) }
                }
                .buttonStyle(.bordered)
                .disabled(isActing)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
        }
        .background(Color(.systemBackground))
    }

    private func filesTab(_ detail: JobDetailDTO) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        if isLoadingFiles && filesRoot.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, Spacing.lg)
                        } else if filesRoot.isEmpty {
                            ContentUnavailableView(
                                "暂无文件",
                                systemImage: "folder",
                                description: Text("这个任务没有可浏览的工作目录文件。")
                            )
                        } else {
                            ForEach(filesRoot) { node in
                                fileTreeNode(node)
                            }
                        }
                    }
                    .padding(Spacing.md)
                }
                .frame(width: max(220, geo.size.width * 0.35))
                .background(Color(.systemBackground))

                Divider()

                Group {
                    if isLoadingFileContent {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let fileContent {
                        ScrollView([.horizontal, .vertical]) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text(fileContent.path)
                                    .font(AppTypography.micro)
                                    .foregroundStyle(AppColors.neutral)
                                Text(fileContent.content)
                                    .font(AppTypography.captionMono)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(Spacing.md)
                        }
                    } else {
                        ContentUnavailableView(
                            "选择文件",
                            systemImage: "doc.text",
                            description: Text(detail.browseUrl == nil ? "当前任务未暴露文件浏览入口。" : "从左侧选择一个文件进行查看。")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.neutral.opacity(0.03))
            }
        }
    }

    @ViewBuilder
    private func fileTreeNode(_ node: JobFileNode) -> some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: Binding(get: { node.isExpanded }, set: { expanded in
                Task { await toggleDirectory(node.id, expanded: expanded) }
            })) {
                if let children = node.children, !children.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(children) { child in
                            fileTreeNode(child)
                        }
                    }
                    .padding(.leading, Spacing.sm)
                } else if node.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.leading, Spacing.sm)
                } else {
                    Text("空文件夹")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                        .padding(.leading, Spacing.sm)
                }
            } label: {
                Label(node.name, systemImage: "folder")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.primaryText)
            }
        } else {
            Button {
                Task { await loadFile(node.path) }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(AppColors.neutral)
                    Text(node.name)
                        .font(AppTypography.caption)
                        .foregroundStyle(selectedFilePath == node.path ? AppColors.primaryAction : AppColors.primaryText)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private func loadDetail(initial: Bool) async {
        do {
            loadError = nil
            let fetched = try await vm.jobDetail(id: jobId)
            detail = fetched
            if initial {
                selectedTab = fetched.canPrompt == true ? .activity : .overview
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadEventsIfNeeded(force: Bool) async {
        guard force || events.isEmpty else { return }
        isLoadingEvents = true
        defer { isLoadingEvents = false }
        do {
            events = try await vm.jobEvents(id: jobId)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func loadFilesIfNeeded(force: Bool) async {
        guard detail?.browseUrl != nil else { return }
        guard force || filesRoot.isEmpty else { return }
        isLoadingFiles = true
        defer { isLoadingFiles = false }
        do {
            let entries = try await vm.jobFiles(id: jobId)
            filesRoot = entries.map(JobFileNode.init(dto:))
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func toggleDirectory(_ path: String, expanded: Bool) async {
        if expanded, let node = findNode(path, in: filesRoot), node.children == nil {
            updateNode(path, in: &filesRoot) { node in
                node.isLoading = true
                node.isExpanded = true
            }
            do {
                let children = try await vm.jobFiles(id: jobId, path: path)
                updateNode(path, in: &filesRoot) { node in
                    node.children = children.map(JobFileNode.init(dto:))
                    node.isExpanded = true
                    node.isLoading = false
                }
            } catch {
                updateNode(path, in: &filesRoot) { node in
                    node.isLoading = false
                    node.isExpanded = false
                }
                actionError = error.localizedDescription
            }
        } else {
            updateNode(path, in: &filesRoot) { node in
                node.isExpanded = expanded
            }
        }
    }

    private func loadFile(_ path: String) async {
        isLoadingFileContent = true
        defer { isLoadingFileContent = false }
        do {
            fileContent = try await vm.readJobFile(id: jobId, path: path)
            selectedFilePath = path
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func sendPrompt(done: Bool) async {
        let content = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard done || !content.isEmpty else { return }
        isActing = true
        defer { isActing = false }
        do {
            _ = try await vm.sendPrompt(
                id: jobId,
                content: done ? (content.isEmpty ? "(done)" : content) : content,
                done: done
            )
            followUpText = ""
            await loadEventsIfNeeded(force: true)
            await loadDetail(initial: false)
            Haptics.shared.refreshComplete()
        } catch {
            actionError = error.localizedDescription
            Haptics.shared.error()
        }
    }

    private func restartJob() async {
        isActing = true
        defer { isActing = false }
        do {
            try await vm.restartJob(id: jobId)
            await vm.load()
            await loadDetail(initial: false)
            await loadEventsIfNeeded(force: true)
            Haptics.shared.refreshComplete()
        } catch {
            actionError = error.localizedDescription
            Haptics.shared.error()
        }
    }

    private func detailSubtitle(_ detail: JobDetailDTO) -> String {
        var parts: [String] = []
        parts.append(stateLabel(detail.state))
        if let created = detail.createdAt, !created.isEmpty {
            parts.append(created)
        }
        return parts.joined(separator: " · ")
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(AppTypography.nano)
            .padding(.horizontal, Spacing.xxs)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }

    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(AppTypography.captionBold)
                .foregroundStyle(AppColors.primaryText)
            content()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private func eventTitle(_ type: String) -> String {
        switch type {
        case "message": return "消息"
        case "tool_use": return "工具调用"
        case "tool_result": return "工具结果"
        case "status": return "状态"
        case "result": return "最终结果"
        default: return type
        }
    }

    private func eventTint(_ type: String) -> Color {
        switch type {
        case "message": return AppColors.metricPrimary
        case "tool_use": return AppColors.info
        case "tool_result": return AppColors.success
        case "status": return AppColors.warning
        case "result": return AppColors.primaryAction
        default: return AppColors.neutral
        }
    }

    private func activitySummary(for event: JobEventDTO) -> String? {
        guard let object = event.data?.objectValue else { return nil }
        switch event.eventType {
        case "message":
            let role = object["role"]?.stringValue ?? "assistant"
            let content = object["content"]?.stringValue ?? ""
            return "\(role): \(content)"
        case "tool_use":
            return object["tool_name"]?.stringValue
        case "tool_result":
            return object["tool_name"]?.stringValue
        case "status":
            return object["message"]?.stringValue
        case "result":
            return object["message"]?.stringValue ?? object["status"]?.stringValue ?? object["error"]?.stringValue
        default:
            return nil
        }
    }

    private func prettyJSON(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        let raw = unwrap(value)
        if let string = raw as? String { return string }
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: raw)
        }
        return string
    }

    private func unwrap(_ value: JSONValue) -> Any {
        switch value {
        case .string(let string):
            return string
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .bool(let bool):
            return bool
        case .array(let array):
            return array.map(unwrap)
        case .object(let object):
            return object.mapValues(unwrap)
        case .null:
            return NSNull()
        }
    }

    private func findNode(_ path: String, in nodes: [JobFileNode]) -> JobFileNode? {
        for node in nodes {
            if node.path == path { return node }
            if let child = findNode(path, in: node.children ?? []) { return child }
        }
        return nil
    }

    private func updateNode(_ path: String, in nodes: inout [JobFileNode], update: (inout JobFileNode) -> Void) {
        for index in nodes.indices {
            if nodes[index].path == path {
                update(&nodes[index])
                return
            }
            if nodes[index].children != nil {
                updateNode(path, in: &nodes[index].children!, update: update)
            }
        }
    }

    private func stateLabel(_ state: String?) -> String {
        switch (state ?? "").lowercased() {
        case "in_progress": return "In Progress"
        case "interrupted": return "Interrupted"
        case nil, "": return "Unknown"
        default: return (state ?? "unknown").capitalized
        }
    }

    private func color(forState state: String?) -> Color {
        switch (state ?? "").lowercased() {
        case "completed": return AppColors.success
        case "in_progress": return AppColors.info
        case "pending": return AppColors.warning
        case "failed", "interrupted", "stuck": return AppColors.danger
        default: return AppColors.neutral
        }
    }

    private func prettyDuration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)s"
    }
}

enum JobDetailTab: CaseIterable, Identifiable {
    case overview, activity, files

    var id: Self { self }
    var title: String {
        switch self {
        case .overview: return "概览"
        case .activity: return "活动"
        case .files: return "文件"
        }
    }
}

enum JobActivityFilter: CaseIterable, Identifiable {
    case all, message, toolUse, toolResult, status

    var id: Self { self }
    var title: String {
        switch self {
        case .all: return "全部"
        case .message: return "消息"
        case .toolUse: return "工具调用"
        case .toolResult: return "结果"
        case .status: return "状态"
        }
    }
}

struct JobFileNode: Identifiable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [JobFileNode]?
    var isExpanded = false
    var isLoading = false

    init(dto: JobFileEntryDTO) {
        id = dto.path
        name = dto.name
        path = dto.path
        isDirectory = dto.isDir
        children = dto.isDir ? [] : nil
    }
}
