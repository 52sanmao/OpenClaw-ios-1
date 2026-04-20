import MarkdownUI
import SwiftUI
import UIKit

struct ChatView: View {
    let client: GatewayClientProtocol
    let memoryVM: MemoryViewModel?
    let cronVM: CronSummaryViewModel?
    let cronDetailRepository: CronDetailRepository?
    let accountStore: AccountStore?

    @State var vm: ChatViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var isBottomAnchorVisible = true
    @State private var bottomAnchorMaxY: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var lastAutoScrollTimestamp: CFAbsoluteTime = 0

    private let messagesScrollSpaceName = "lingkong-chat-scroll-space"
    private let bottomScrollAnchorId = "lingkong-chat-scroll-bottom-anchor"
    private let autoScrollThrottleInterval: CFAbsoluteTime = 0.12

    init(
        vm: ChatViewModel,
        client: GatewayClientProtocol,
        memoryVM: MemoryViewModel? = nil,
        cronVM: CronSummaryViewModel? = nil,
        cronDetailRepository: CronDetailRepository? = nil,
        accountStore: AccountStore? = nil
    ) {
        _vm = State(initialValue: vm)
        self.client = client
        self.memoryVM = memoryVM
        self.cronVM = cronVM
        self.cronDetailRepository = cronDetailRepository
        self.accountStore = accountStore
    }

    var body: some View {
        ChatScreenShell(
            topBanner: { topBannerView },
            timeline: { messagesScrollView },
            inputHeader: { toolbarSectionView },
            composer: { inputSectionView }
        )
        .toolbar {
            navigationTitleItem
            ToolbarItem(placement: .primaryAction) {
                if vm.isStreaming {
                    Button { vm.cancel() } label: {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(AppColors.danger)
                    }
                    .accessibilityLabel("停止生成")
                } else {
                    Button {
                        vm.reloadHistory()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isLoadingHistory)
                    .accessibilityLabel("重新加载历史")
                }
            }
        }
        .refreshable {
            await vm.loadHistory()
            Haptics.shared.refreshComplete()
        }
        .task { await vm.loadHistory() }
    }

    @ViewBuilder
    private var topBannerView: some View {
        if vm.isStreaming {
            HStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text("代理正在对话中…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if vm.messages.isEmpty && !vm.isLoadingHistory {
                        emptyState
                    }

                    if vm.isLoadingHistory {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }

                    ForEach(vm.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .padding(.leading, 16)
                            .padding(.trailing, message.role == .user ? 12 : 16)
                    }

                    if vm.isStreaming {
                        agentStateFooterView
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomScrollAnchorId)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ChatBottomAnchorMaxYPreferenceKey.self,
                                    value: geometry.frame(in: .named(messagesScrollSpaceName)).maxY
                                )
                            }
                        )
                }
                .padding(.vertical)
            }
            .coordinateSpace(name: messagesScrollSpaceName)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ChatScrollViewportHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            .onPreferenceChange(ChatBottomAnchorMaxYPreferenceKey.self) { value in
                if abs(bottomAnchorMaxY - value) > 0.5 {
                    bottomAnchorMaxY = value
                }
                updateBottomAnchorVisibility(anchorMaxY: value)
            }
            .onPreferenceChange(ChatScrollViewportHeightPreferenceKey.self) { value in
                if abs(scrollViewportHeight - value) > 0.5 {
                    scrollViewportHeight = value
                    updateBottomAnchorVisibility(anchorMaxY: bottomAnchorMaxY)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10).onChanged { _ in
                    if isInputFocused {
                        dismissKeyboard()
                    }
                }
            )
            .onChange(of: vm.messages.count) { _, _ in
                if !vm.messages.isEmpty {
                    guard isBottomAnchorVisible || vm.messages.count == 1 else { return }
                    performAutoScroll(proxy, animated: true, throttled: false)
                }
            }
            .onChange(of: vm.messages.last?.content) { _, _ in
                if let lastMessage = vm.messages.last, lastMessage.isStreaming {
                    guard isBottomAnchorVisible else { return }
                    performAutoScroll(proxy, animated: false, throttled: true)
                }
            }
            .onChange(of: isInputFocused) { _, newValue in
                if newValue, !vm.messages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        performAutoScroll(proxy, animated: true, throttled: false)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if shouldShowScrollToBottomButton {
                    Button {
                        isBottomAnchorVisible = true
                        performAutoScroll(proxy, animated: true, throttled: false)
                    } label: {
                        Image(systemName: "arrow.down.to.line.compact")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.blue))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                    .padding(.bottom, 72)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
        }
    }

    private var shouldShowScrollToBottomButton: Bool {
        !vm.messages.isEmpty && !isBottomAnchorVisible
    }

    @ViewBuilder
    private var agentStateFooterView: some View {
        HStack {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("生成中…")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.1))
            .cornerRadius(16)
            .padding(.leading, 16)
            Spacer()
        }
    }

    @ViewBuilder
    private var toolbarSectionView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                NavigationLink {
                    TokenDetailView(vm: TokenUsageViewModel(client: client), detailRepository: cronDetailRepository ?? RemoteCronDetailRepository(client: client))
                } label: {
                    chatQuickPill(icon: "chart.bar.fill", label: "令牌")
                }
                .buttonStyle(.plain)

                if let cronVM, let cronDetailRepository {
                    NavigationLink {
                        CronsTab(vm: cronVM, detailRepository: cronDetailRepository, client: client)
                    } label: {
                        chatQuickPill(icon: "clock.fill", label: "定时任务")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 6)
        .frame(height: 44)
    }

    @ViewBuilder
    private func chatQuickPill(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.blue)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.blue.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var inputSectionView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField(
                    "输入消息…",
                    text: $inputText,
                    axis: .vertical
                )
                .font(.system(size: 17))
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .frame(minHeight: 40, alignment: .topLeading)

                HStack(spacing: 12) {
                    Spacer()

                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .padding(.top, 4)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isInputFocused ? Color.blue.opacity(0.36) : Color(uiColor: .separator).opacity(0.24),
                        lineWidth: isInputFocused ? 1.5 : 1
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.neutral.opacity(0.3))
            Text("向你的代理发送一条消息。")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.neutral)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private var navigationTitleItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(AppColors.primaryAction)
                    Circle()
                        .fill(vm.isStreaming ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .shadow(radius: 1)
                        .offset(x: -2, y: -2)
                }
                .frame(width: 24, height: 24)
                Text("灵控")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        dismissKeyboard()
        inputText = ""
        vm.send(text)
    }

    private func dismissKeyboard() {
        isInputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func updateBottomAnchorVisibility(anchorMaxY: CGFloat) {
        guard scrollViewportHeight > 0 else { return }
        let threshold: CGFloat = 24
        let visible = anchorMaxY <= (scrollViewportHeight + threshold)
        if visible != isBottomAnchorVisible {
            isBottomAnchorVisible = visible
        }
    }

    private func performAutoScroll(
        _ proxy: ScrollViewProxy,
        animated: Bool,
        throttled: Bool
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        if throttled, (now - lastAutoScrollTimestamp) < autoScrollThrottleInterval {
            return
        }
        lastAutoScrollTimestamp = now

        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomScrollAnchorId, anchor: .bottom)
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                proxy.scrollTo(bottomScrollAnchorId, anchor: .bottom)
            }
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    @State private var copied = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            if isUser {
                Spacer(minLength: 56)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.xs) {
                if message.isStreaming && !isUser {
                    Text("灵控")
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                        .padding(.leading, Spacing.xs)
                }

                bubbleBody
                    .frame(maxWidth: 320, alignment: isUser ? .trailing : .leading)

                messageMeta
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 56)
            }
        }
    }

    @ViewBuilder
    private var bubbleBody: some View {
        if message.isStreaming && message.content.isEmpty {
            bubbleSurface {
                HStack(spacing: Spacing.xs) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(AppColors.neutral.opacity(0.45))
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(minHeight: 22)
            }
        } else if isUser {
            bubbleSurface {
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white)
                    .textSelection(.enabled)
            }
        } else {
            bubbleSurface {
                Markdown(message.content)
                    .markdownTheme(.openClaw)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var messageMeta: some View {
        if message.isStreaming {
            HStack(spacing: Spacing.xxs) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("正在输入…")
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
            }
            .padding(.horizontal, Spacing.xs)
        } else {
            HStack(spacing: Spacing.xs) {
                Text(message.timestamp, style: .time)
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)

                if !isUser {
                    Button {
                        Formatters.copyToClipboard(message.content, copied: $copied)
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(AppTypography.nano)
                            .foregroundStyle(copied ? AppColors.success : AppColors.neutral)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copied ? "已复制" : "复制消息")
                }
            }
            .padding(.horizontal, Spacing.xs)
        }
    }

    @ViewBuilder
    private func bubbleSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Spacing.sm + Spacing.xxs)
            .padding(.vertical, Spacing.sm)
            .background(bubbleBackground)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: AppRadius.card,
                    bottomLeadingRadius: isUser ? AppRadius.card : AppRadius.sm,
                    bottomTrailingRadius: isUser ? AppRadius.sm : AppRadius.card,
                    topTrailingRadius: AppRadius.card,
                    style: .continuous
                )
            )
            .overlay {
                if !isUser {
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppRadius.card,
                        bottomLeadingRadius: AppRadius.sm,
                        bottomTrailingRadius: AppRadius.card,
                        topTrailingRadius: AppRadius.card,
                        style: .continuous
                    )
                    .strokeBorder(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
                }
            }
            .shadow(color: Color.black.opacity(isUser ? 0.08 : 0.05), radius: 10, x: 0, y: 4)
    }

    private var bubbleBackground: some ShapeStyle {
        if isUser {
            AppColors.primaryAction
        } else {
            Color(uiColor: .systemBackground)
        }
    }
}

private struct ChatBottomAnchorMaxYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatScrollViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatScreenShell<TopBanner: View, Timeline: View, InputHeader: View, Composer: View>: View {
    let backgroundColor: Color
    let topBanner: TopBanner
    let timeline: Timeline
    let inputHeader: InputHeader
    let composer: Composer

    init(
        backgroundColor: Color = Color(.systemGroupedBackground),
        @ViewBuilder topBanner: () -> TopBanner,
        @ViewBuilder timeline: () -> Timeline,
        @ViewBuilder inputHeader: () -> InputHeader,
        @ViewBuilder composer: () -> Composer
    ) {
        self.backgroundColor = backgroundColor
        self.topBanner = topBanner()
        self.timeline = timeline()
        self.inputHeader = inputHeader()
        self.composer = composer()
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBanner
                timeline
                inputHeader
                composer
            }
        }
    }
}
