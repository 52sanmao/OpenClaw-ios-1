import SwiftUI

struct SettingsImportSheet: View {
    let adminVM: AdminViewModel
    let onClose: () -> Void

    @State private var jsonText = ""
    @State private var isSubmitting = false
    @State private var submitError: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                Text("将之前导出的配置 JSON 粘贴到下方，然后点击「导入」即可恢复网关配置。")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.neutral)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)

                TextEditor(text: $jsonText)
                    .font(AppTypography.captionMono)
                    .focused($isFocused)
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .fill(Color(.systemGroupedBackground))
                    )
                    .frame(minHeight: 200)
                    .padding(.horizontal, Spacing.md)

                Spacer()
            }
            .padding(.vertical, Spacing.sm)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("导入配置")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { onClose() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("导入")
                        }
                    }
                    .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .alert("导入失败", isPresented: Binding(
                get: { submitError != nil },
                set: { if !$0 { submitError = nil } }
            )) {
                Button("确定", role: .cancel) { submitError = nil }
            } message: {
                Text(submitError ?? "")
            }
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await adminVM.importSettingsJSON(jsonText)
            Haptics.shared.success()
            onClose()
        } catch {
            submitError = error.localizedDescription
            Haptics.shared.error()
        }
    }
}
