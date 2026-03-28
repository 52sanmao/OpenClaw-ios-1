import Foundation
import SwiftUI
import UIKit

/// Cached formatters — never create DateFormatter/RelativeDateTimeFormatter in computed properties or view bodies.
enum Formatters {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static let absoluteDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func relativeString(for date: Date) -> String {
        relative.localizedString(for: date, relativeTo: Date())
    }

    static func absoluteString(for date: Date) -> String {
        absoluteDate.string(from: date)
    }

    /// Format token counts: 1234 → "1.2k", 1234567 → "1.2M"
    static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1000 { return String(format: "%.1fk", Double(count) / 1000) }
        return "\(count)"
    }

    /// Shorten model identifiers: "github-copilot/claude-3-5-sonnet" → "3.5.sonnet"
    static func modelShortName(_ model: String) -> String {
        let cleaned = model
            .replacingOccurrences(of: "github-copilot/", with: "")
            .replacingOccurrences(of: "anthropic/", with: "")
            .replacingOccurrences(of: "claude-", with: "")
        let parts = cleaned.split(separator: "-")
        guard parts.count >= 2 else { return cleaned }
        let name = parts[0].prefix(1).uppercased() + parts[0].dropFirst()
        let version = parts[1...].joined(separator: ".")
        return "\(name) \(version)"
    }

    /// Copy text to pasteboard with haptic feedback. Returns a Task that resets the `copied` binding after 2s.
    @MainActor
    static func copyToClipboard(_ text: String, copied: Binding<Bool>? = nil) {
        UIPasteboard.general.string = text
        Haptics.shared.success()
        if let copied {
            copied.wrappedValue = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied.wrappedValue = false
            }
        }
    }
}
