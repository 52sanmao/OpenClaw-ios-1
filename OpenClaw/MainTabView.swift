import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Root navigation — tab bar on iOS, sidebar on macOS.
struct MainTabView: View {
    let accountStore: AccountStore
    private let client: GatewayClientProtocol
    private let cronDetailRepo: CronDetailRepository
    private let sessionRepo: SessionRepository

    @State private var cronVM: CronSummaryViewModel
    @State private var memoryVM: MemoryViewModel
    @State private var sessionsVM: SessionsViewModel
    @StateObject private var appLogStore = AppLogStore.shared
    @State private var showLogViewer = false
    @State private var showCopyAlert = false
    @State private var logButtonOffset = LogButtonPositionStore.load()
    @State private var dragStartOffset: CGSize?

    init(accountStore: AccountStore) {
        self.accountStore = accountStore
        guard let client = GatewayClient(accountStore: accountStore) else {
            fatalError("MainTabView created without a configured account")
        }
        self.client = client
        self.cronDetailRepo = RemoteCronDetailRepository(client: client)
        let sessionRepo = RemoteSessionRepository(client: client)
        self.sessionRepo = sessionRepo
        _cronVM = State(initialValue: CronSummaryViewModel(repository: RemoteCronRepository(client: client)))
        _memoryVM = State(initialValue: MemoryViewModel(
            repository: RemoteMemoryRepository(client: client, sessionKey: SessionKeys.main, workspaceRoot: AppConstants.workspaceRoot),
            client: client
        ))
        _sessionsVM = State(initialValue: SessionsViewModel(repository: sessionRepo))
    }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    // MARK: - iOS (Tab Bar)

    #if !os(macOS)
    private var iosBody: some View {
        TabView {
            Tab("会话", systemImage: "bubble.left.and.text.bubble.right") {
                SessionsView(vm: sessionsVM, repository: sessionRepo, client: client)
            }
            Tab("首页", systemImage: "house.fill") {
                HomeView(accountStore: accountStore, client: client, cronVM: cronVM, cronDetailRepository: cronDetailRepo)
            }
            Tab("定时任务", systemImage: "clock.arrow.2.circlepath") {
                CronsTab(vm: cronVM, detailRepository: cronDetailRepo, client: client)
            }
            Tab("记忆与技能", systemImage: "brain") {
                MemoryTab(vm: memoryVM)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if AppDebugSettings.debugEnabled {
                GeometryReader { geometry in
                    Button {
                        showLogViewer = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(AppColors.metricPrimary)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    }
                    .offset(x: logButtonOffset.width, y: logButtonOffset.height)
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                if dragStartOffset == nil {
                                    dragStartOffset = logButtonOffset
                                }
                                guard let start = dragStartOffset else { return }
                                logButtonOffset = clampedLogOffset(
                                    start: start,
                                    translation: value.translation,
                                    in: geometry.size
                                )
                            }
                            .onEnded { value in
                                let start = dragStartOffset ?? logButtonOffset
                                let newOffset = clampedLogOffset(
                                    start: start,
                                    translation: value.translation,
                                    in: geometry.size
                                )
                                logButtonOffset = newOffset
                                LogButtonPositionStore.save(newOffset)
                                dragStartOffset = nil
                            }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, Spacing.md)
                    .padding(.bottom, 88)
                    .accessibilityLabel("查看日志")
                }
            }
        }
        .sheet(isPresented: $showLogViewer) {
            NavigationStack {
                ScrollView {
                    Text(appLogStore.exportText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("开爪日志")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { showLogViewer = false }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("清空") {
                            appLogStore.clear()
                        }
                        Button("复制") {
                            UIPasteboard.general.string = appLogStore.exportText
                            showCopyAlert = true
                        }
                    }
                }
            }
        }
        .alert("已复制日志", isPresented: $showCopyAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("复制内容已包含 App 名称和版本。")
        }
    }

    private func clampedLogOffset(start: CGSize, translation: CGSize, in size: CGSize) -> CGSize {
        let proposedWidth = start.width + translation.width
        let proposedHeight = start.height + translation.height
        let maxHorizontal = max(size.width - 120, 0)
        let maxUpward = max(size.height - 220, 0)

        return CGSize(
            width: min(max(proposedWidth, -maxHorizontal), 0),
            height: min(max(proposedHeight, -maxUpward), 0)
        )
    }
    #endif

    // MARK: - macOS (Sidebar)

    #if os(macOS)
    @State private var selection: SidebarItem? = .home

    enum SidebarItem: String, CaseIterable, Identifiable {
        case home = "首页"
        case crons = "定时任务"
        case memSkills = "记忆与技能"
        case sessions = "会话"
        case chat = "聊天"
        case settings = "设置"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .home: "house.fill"
            case .crons: "clock.arrow.2.circlepath"
            case .memSkills: "brain"
            case .sessions: "bubble.left.and.text.bubble.right"
            case .chat: "bubble.left.and.bubble.right"
            case .settings: "gear"
            }
        }
    }

    private var macBody: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
            }
            .navigationTitle("开爪")
        } detail: {
            switch selection {
            case .home:
                HomeView(accountStore: accountStore, client: client, cronVM: cronVM, cronDetailRepository: cronDetailRepo)
            case .crons:
                CronsTab(vm: cronVM, detailRepository: cronDetailRepo, client: client)
            case .memSkills:
                MemoryTab(vm: memoryVM)
            case .sessions:
                SessionsView(vm: sessionsVM, repository: sessionRepo, client: client)
            case .chat:
                ChatTab(client: client)
            case .settings:
                SettingsView(accountStore: accountStore, client: client)
            case nil:
                Text("请选择一个项目")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
    #endif
}

private enum LogButtonPositionStore {
    private static let widthKey = "openclaw.logButton.offset.width"
    private static let heightKey = "openclaw.logButton.offset.height"

    static func load() -> CGSize {
        CGSize(
            width: UserDefaults.standard.double(forKey: widthKey),
            height: UserDefaults.standard.double(forKey: heightKey)
        )
    }

    static func save(_ offset: CGSize) {
        UserDefaults.standard.set(offset.width, forKey: widthKey)
        UserDefaults.standard.set(offset.height, forKey: heightKey)
    }
}
