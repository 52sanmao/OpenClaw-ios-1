import SwiftUI

/// Reusable model name pill (capsule badge) used across cron runs, investigations, and trace views.
struct ModelPill: View {
    let model: String

    var body: some View {
        Text(Formatters.modelShortName(model))
            .font(AppTypography.micro)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background(AppColors.pillBackground, in: Capsule())
            .foregroundStyle(AppColors.pillForeground)
    }
}
