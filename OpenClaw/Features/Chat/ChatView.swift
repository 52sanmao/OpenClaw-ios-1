import MarkdownUI
import SwiftUI
import UIKit

struct ChatView: View {
    @State var vm: ChatViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

            Divider()
                .opacity(0.35)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        if vm.messages.isEmpty && !vm.isLoadingHistory {
                            emptyState
                        } else {
                            timelineStatusCard
                        }

                        if vm.isLoadingHistory {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, Spacing.xl)
                        }

                        ForEach(vm.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10).onChanged { _ in
                        dismissKeyboard()
                    }
                )
                .onChange(of: vm.messages.last?.content) {
                    if let last = vm.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if let error = vm.error {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.danger)
                    Text(error.localizedDescription)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.danger)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
            }

            Divider()
                .opacity(0.35)

            CommentInputBar(
                placeholder: vm.isStreaming ? "正在生成回复…可在右上角停止" : "向你的代理发送消息…",
                text: $inputText
            ) { submitted in
                let text = submitted.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                dismissKeyboard()
                inputText = ""
                vm.send(text)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("聊天")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .task { await vm.loadHistory() }
    }

    private var chatHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.primaryAction)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("持续对话")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(.primary)
                    Text(vm.isStreaming ? "代理正在生成回复，可随时使用右上角停止按钮。" : "消息会按当前线程连续保存与加载。")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }

                Spacer()
            }

            if vm.isStreaming {
                HStack(spacing: Spacing.xxs) {
                    Circle()
                        .fill(AppColors.success)
                        .frame(width: 8, height: 8)
                    Text("生成中")
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .padding(Spacing.md)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card)
                .strokeBorder(AppColors.cardBorder, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var timelineStatusCard: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: vm.isStreaming ? "waveform.badge.magnifyingglass" : "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .foregroundStyle(vm.isStreaming ? AppColors.success : AppColors.neutral)
            Text(vm.isStreaming ? "正在流式输出最新回复" : "已载入当前线程的最近消息")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.neutral)
            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(AppColors.neutral.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.neutral.opacity(0.3))
            Text("向你的代理发送一条消息。")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.neutral)
                .multilineTextAlignment(.center)
            Text("发送后会继续沿用当前线程；当代理开始回复时，右上角会显示停止按钮。")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.neutral)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxl)
    }

    private func dismissKeyboard() {
        isInputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage
    @State private var copied = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.xxs) {
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                if !isUser {
                    avatar(symbol: "sparkles", tint: AppColors.metricPrimary)
                }

                if isUser { Spacer(minLength: Spacing.xxl) }

                bubbleBody
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

                if !isUser { Spacer(minLength: Spacing.xxl) }

                if isUser {
                    avatar(symbol: "person.fill", tint: AppColors.primaryAction)
                }
            }

            HStack(spacing: Spacing.sm) {
                if isUser { Spacer() }

                if message.isStreaming && !message.content.isEmpty {
                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(AppColors.success)
                            .frame(width: 6, height: 6)
                        Text("流式输出中")
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                } else if !message.content.isEmpty && !message.isStreaming {
                    Text(Formatters.relativeString(for: message.timestamp))
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
                    }
                }

                if !isUser { Spacer() }
            }
            .padding(.horizontal, isUser ? 44 : 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "你" : "代理"): \(message.content)")
    }

    @ViewBuilder
    private var bubbleBody: some View {
        if isUser {
            Text(message.content)
                .font(AppTypography.body)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(AppColors.primaryAction, in: RoundedRectangle(cornerRadius: AppRadius.card))
                .foregroundStyle(.white)
        } else if message.content.isEmpty && message.isStreaming {
            HStack(spacing: Spacing.xs) {
                ProgressView().scaleEffect(0.7)
                Text("思考中…")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.neutral)
            }
            .padding(Spacing.sm)
            .background(
                AppColors.neutral.opacity(0.08),
                in: RoundedRectangle(cornerRadius: AppRadius.card)
            )
        } else {
            Markdown(message.content)
                .markdownTheme(.openClaw)
                .textSelection(.enabled)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    AppColors.neutral.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: AppRadius.card)
                )
        }
    }

    private func avatar(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(AppTypography.nano)
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(tint.opacity(0.12), in: Circle())
    }
}
