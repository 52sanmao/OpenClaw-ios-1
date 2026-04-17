import SwiftUI

struct SettingsView: View {
    var accountStore: AccountStore
    var client: GatewayClientProtocol?

    @State private var showAddAccount = false
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var accountToDelete: GatewayAccount?
    @State private var connectionDetails: [String] = []
    @State private var showConnectionDetails = false
    @State private var debugEnabled = AppDebugSettings.debugEnabled

    var body: some View {
        List {
            if let active = accountStore.activeAccount {
                Section {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(AppColors.success)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(active.name)
                                .font(AppTypography.body)
                                .fontWeight(.medium)
                            Text(active.displayURL)
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.neutral)
                        }
                        Spacer()
                        Text("当前使用")
                            .font(AppTypography.nano)
                            .padding(.horizontal, Spacing.xxs)
                            .padding(.vertical, 2)
                            .background(AppColors.success.opacity(0.15), in: Capsule())
                            .foregroundStyle(AppColors.success)
                    }
                } header: {
                    Text("当前账号")
                }
            }

            if accountStore.accounts.count > 1 {
                Section("切换账号") {
                    ForEach(accountStore.accounts) { account in
                        Button {
                            accountStore.setActive(account.id)
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: account.id == accountStore.activeAccountId ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(account.id == accountStore.activeAccountId ? AppColors.success : AppColors.neutral)
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(account.name)
                                        .font(AppTypography.body)
                                    Text(account.displayURL)
                                        .font(AppTypography.micro)
                                        .foregroundStyle(AppColors.neutral)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                accountToDelete = account
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    showAddAccount = true
                } label: {
                    Label("添加账号", systemImage: "plus.circle")
                }
            }

            Section("IronClaw") {
                LabeledContent("Agent", value: AppConstants.agentId.capitalized)
            }

            Section("调试") {
                Toggle("调试模式", isOn: $debugEnabled)
                    .onChange(of: debugEnabled) { _, newValue in
                        AppDebugSettings.debugEnabled = newValue
                        if !newValue {
                            AppLogStore.shared.clear()
                        }
                    }
                Text(debugEnabled ? "已开启调试日志、日志按钮和调试输出。" : "已关闭调试日志、日志按钮和调试输出。")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            Section {
                Button(action: runConnectionTest) {
                    HStack {
                        Label("测试连接", systemImage: "network")
                        Spacer()
                        if isTesting { ProgressView().scaleEffect(0.8) }
                    }
                }
                .disabled(isTesting || !accountStore.isConfigured)

                if let result = testResult {
                    Label(result.message, systemImage: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(AppTypography.captionMono)
                        .foregroundStyle(result.isSuccess ? AppColors.success : AppColors.danger)
                        .textSelection(.enabled)
                }

                if !connectionDetails.isEmpty {
                    Button(showConnectionDetails ? "隐藏诊断详情" : "查看诊断详情") {
                        showConnectionDetails.toggle()
                    }

                    if showConnectionDetails {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            ForEach(Array(connectionDetails.enumerated()), id: \.offset) { _, detail in
                                Text("• \(detail)")
                                    .font(AppTypography.captionMono)
                                    .foregroundStyle(AppColors.neutral)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("连接测试会依次检查 /v1/models、/api/chat/thread/new、/api/chat/send 与 /api/chat/history。成功代表聊天主链路可用；即使某些扩展页面缺少接口，聊天与定时任务仍可继续使用。")
            }

            Section("关于") {
                LabeledContent("应用") {
                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        Text("开爪")
                            .font(AppTypography.body)
                        Text("IronClaw iOS 客户端")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
                LabeledContent("文档", value: "docs.openclaw.ai")
                LabeledContent("源码", value: "github.com/openclaw")
                LabeledContent("账号数", value: "\(accountStore.accounts.count)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddAccount) {
            AddAccountView(accountStore: accountStore)
        }
        .alert("删除账号？", isPresented: Binding(
            get: { accountToDelete != nil },
            set: { if !$0 { accountToDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let account = accountToDelete {
                    accountStore.delete(account.id)
                }
            }
            Button("取消", role: .cancel) { accountToDelete = nil }
        } message: {
            if let account = accountToDelete {
                Text("要移除“\(account.name)”吗？对应 Token 也会从 Keychain 中删除。")
            }
        }
    }

    private func runConnectionTest() {
        isTesting = true
        testResult = nil
        connectionDetails = []
        showConnectionDetails = false
        guard let client else { return }
        Task {
            do {
                let result = try await client.validateGatewayConnection(testMessage: "Hello from OpenClaw settings")
                testResult = TestResult(
                    isSuccess: true,
                    message: result.summary
                )
                connectionDetails = result.details
                AppLogStore.shared.append("连接测试成功：\(result.summary)")
                for detail in result.details {
                    AppLogStore.shared.append(detail)
                }
                Haptics.shared.success()
            } catch {
                let failure = error.localizedDescription
                AppLogStore.shared.append("连接测试失败：\(failure)")
                connectionDetails = [
                    "聊天主链路验证失败：\(failure)",
                    "请检查 /v1/models、/api/chat/thread/new、/api/chat/send、/api/chat/history 的服务端日志与网关鉴权配置。",
                    "右下角日志浮窗会记录每个请求阶段，便于确认究竟失败在模型探活、建线程、发送还是历史轮询。"
                ]
                showConnectionDetails = true
                testResult = TestResult(isSuccess: false, message: failure)
                Haptics.shared.error()
            }
            isTesting = false
        }
    }
}

private struct TestResult {
    let isSuccess: Bool
    let message: String
}

private enum AppDebugSettings {
    private static let key = "openclaw.debug.enabled"

    static var debugEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
