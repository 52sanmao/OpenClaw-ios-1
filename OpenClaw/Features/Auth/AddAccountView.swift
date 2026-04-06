import SwiftUI

/// Add a new gateway account (used for first setup and adding additional accounts).
struct AddAccountView: View {
    var accountStore: AccountStore
    var onDone: (() -> Void)?

    @State private var nameInput = ""
    @State private var urlInput = ""
    @State private var tokenInput = ""
    @State private var agentIdInput = "orchestrator"
    @State private var workspacePathInput = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    private var canConnect: Bool {
        !urlInput.trimmingCharacters(in: .whitespaces).isEmpty
        && !tokenInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image("openclaw")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)

            VStack(spacing: Spacing.xs) {
                Text(accountStore.accounts.isEmpty ? "Connect to Gateway" : "Add Account")
                    .font(AppTypography.screenTitle)
                Text("Enter your gateway URL and Bearer token.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.neutral)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                // Name
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("NAME")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    TextField("My Server", text: $nameInput)
                        .autocorrectionDisabled()
                        .padding(Spacing.sm)
                        .background(AppColors.neutral.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.md))
                }

                // URL
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("GATEWAY URL")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    TextField("https://your-gateway.example.com", text: $urlInput)
                        #if os(iOS)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .padding(Spacing.sm)
                        .background(AppColors.neutral.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.md))
                }

                // Token
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("BEARER TOKEN")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    SecureField("Paste token here\u{2026}", text: $tokenInput)
                        #if os(iOS)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .padding(Spacing.sm)
                        .background(AppColors.neutral.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.md))
                }

                // Agent ID
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

                // Workspace path (optional override)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("WORKSPACE PATH")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                    TextField("auto (based on Agent ID)", text: $workspacePathInput)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                        .padding(Spacing.sm)
                        .background(AppColors.neutral.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.md))
                    Text("Leave empty for default. Set to ~/.openclaw/workspace/ for flat layouts.")
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
                        Text("Connect")
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
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let name = nameInput.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? (URL(string: urlInput)?.host() ?? "Gateway") : name

        do {
            let agent = agentIdInput.trimmingCharacters(in: .whitespaces)
            try accountStore.add(
                name: finalName,
                url: urlInput,
                token: tokenInput,
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
