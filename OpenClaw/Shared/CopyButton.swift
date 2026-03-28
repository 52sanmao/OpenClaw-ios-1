import SwiftUI

/// Reusable full-width copy button with success state feedback.
struct CopyButton: View {
    let text: String
    let label: String
    @State private var copied = false

    init(_ text: String, label: String = "Copy") {
        self.text = text
        self.label = label
    }

    var body: some View {
        Button { Formatters.copyToClipboard(text, copied: $copied) } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                Text(copied ? "Copied" : label)
            }
            .font(AppTypography.caption)
            .foregroundStyle(copied ? AppColors.success : AppColors.primaryAction)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xs)
            .background(
                AppColors.tintedBackground(copied ? AppColors.success : AppColors.primaryAction),
                in: RoundedRectangle(cornerRadius: AppRadius.sm)
            )
        }
    }
}

/// Toolbar copy icon with success state feedback.
struct CopyToolbarButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button { Formatters.copyToClipboard(text, copied: $copied) } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
        }
    }
}
