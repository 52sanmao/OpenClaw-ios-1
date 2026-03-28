import SwiftUI

/// Reusable chat-style input bar with multiline text field and send button.
/// Used across comment sheets, page instructions, and any text submission UI.
struct CommentInputBar: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: (String) -> Void
    @FocusState private var isFocused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center, spacing: Spacing.sm) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(AppTypography.body)
                    .lineLimit(1...8)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs + 2)
                    .background(AppColors.neutral.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                    .focused($isFocused)

                Button {
                    guard !trimmed.isEmpty else { return }
                    onSubmit(trimmed)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(trimmed.isEmpty ? AppColors.neutral : AppColors.primaryAction)
                }
                .disabled(trimmed.isEmpty)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .onAppear { isFocused = true }
    }
}
