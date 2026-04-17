import SwiftUI

/// Add a new gateway account (used for first setup and adding additional accounts).
struct AddAccountView: View {
    private enum DefaultGatewayConfig {
        static let baseURL = "https://rare-lark.agent4.near.ai/"
        static let token = "b5af51dc17344eab80981e47f5ab5784a0f1df4846e7229fba421ae97021aa1e"
    }

    var accountStore: AccountStore
    var onDone: (() -> Void)?

    @State private var nameInput = ""
    @State private var urlInput = DefaultGatewayConfig.baseURL
    @State private var tokenInput = DefaultGatewayConfig.token
    @State private var agentIdInput = "orchestrator"
    @State private var workspacePathInput = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    private var canConnect: Bool {
        let parsed = GatewayAccount.parseBaseURLAndToken(urlInput)
        let explicitToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return !parsed.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!explicitToken.isEmpty || parsed.token != nil)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image("openclaw")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)

            VStack(spacing: Spacing.xs) {
                Text(accountStore.accounts.isEmpty ? "连接 IronClaw" : "添加账号")
                    .font(AppTypography.screenTitle)
                Text("请输入真正提供 IronClaw API 的服务地址和 Bearer Token，不要填写只会打开控制台页面的 URL。")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.neutral)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("名称")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    TextField("我的服务器", text: $nameInput)
                        .autocorrectionDisabled()
                        .padding(Spacing.sm)
                        .background(AppColors.neutral.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.md))
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("IronClaw 地址")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    TextField("https://gateway.example.com", text: $urlInput)
                        #if os(iOS)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .padding(Spacing.sm)
                        .background(AppColors.neutral.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.md))
                    Text("此应用通过 IronClaw HTTP API 工作。这里应填写 API 根地址；如果这个地址打开后只返回控制台 HTML，聊天、工具和 stats 都会失败。")
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("BEARER TOKEN")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    SecureField("在此粘贴 Token…", text: $tokenInput)
                        #if os(iOS)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .padding(Spacing.sm)
                        .background(AppColors.neutral.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.md))
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("AGENT ID")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    TextField("orchestrator", text: $agentIdInput)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .padding(Spacing.sm)
                        .background(AppColors.neutral.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.md))
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("工作区路径")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    TextField("自动（根据 Agent ID 推导）", text: $workspacePathInput)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                        .padding(Spacing.sm)
                        .background(AppColors.neutral.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.md))
                    Text("留空则使用默认路径。若是平铺目录，可改成 ~/.ironclaw/workspace/。")
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: save) {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("连接")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.sm + 2)
            }
            .background(AppColors.primaryAction, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            .foregroundStyle(.white)
            .disabled(!canConnect || isSaving)

            Spacer()
        }
        .padding(Spacing.xl)
        .onAppear {
            if urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                urlInput = DefaultGatewayConfig.baseURL
            }
            if tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tokenInput = DefaultGatewayConfig.token
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let parsed = GatewayAccount.parseBaseURLAndToken(urlInput)
        let normalizedURL = parsed.baseURL
        let resolvedToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (parsed.token ?? "")
            : tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = nameInput.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? (URL(string: normalizedURL)?.host() ?? "IronClaw") : name

        do {
            let agent = agentIdInput.trimmingCharacters(in: .whitespaces)
            try accountStore.add(
                name: finalName,
                url: urlInput,
                token: resolvedToken,
                agentId: agent.isEmpty ? "orchestrator" : agent,
                workspacePath: workspacePathInput
            )
            Haptics.shared.success()
            onDone?()
            dismiss()
        } catch {
            Haptics.shared.error()
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
