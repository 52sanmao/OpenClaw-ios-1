import Foundation

/// A user comment on a specific trace step.
struct TraceComment: Identifiable, Sendable {
    let id: UUID
    let stepId: String
    let stepTitle: String
    let stepTimestamp: String?
    let stepPreview: String
    let text: String

    init(step: TraceStep, text: String) {
        self.id = UUID()
        self.stepId = step.id
        self.stepTitle = step.title
        self.stepTimestamp = step.timestampFormatted
        self.stepPreview = step.contentPreview
        self.text = text
    }
}
