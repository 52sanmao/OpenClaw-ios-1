import Foundation

/// Centralized prompt templates for agent-mediated actions.
/// Edit this file to tune prompts — all templates in one place.
enum PromptTemplates {

    /// Build a prompt for editing a memory file based on user comments.
    static func editMemoryFile(
        path: String,
        content: String,
        comments: [MemoryComment]
    ) -> (system: String, user: String) {
        let system = """
        You are editing a workspace memory file. Apply the user's comments precisely. \
        Rules:
        - Only modify sections mentioned in the comments
        - Preserve all other content exactly as-is
        - Maintain the existing markdown formatting and structure
        - If a comment says to add content, insert it at the specified location
        - If a comment says to remove or reword, do so cleanly
        - Output the COMPLETE updated file content — not a diff, not a partial
        - Do not add commentary — just output the file
        """

        var commentLines: [String] = []
        for (index, comment) in comments.enumerated() {
            commentLines.append("""
            Comment \(index + 1) (lines \(comment.lineStart + 1)-\(comment.lineEnd + 1)):
            Context: "\(comment.paragraphPreview)"
            Request: \(comment.text)
            """)
        }

        let user = """
        File: `\(path)`

        ---
        CURRENT CONTENT:
        \(content)
        ---

        COMMENTS TO APPLY:
        \(commentLines.joined(separator: "\n\n"))

        Apply all comments and return the complete updated file.
        """

        return (system: system, user: user)
    }

    /// Build a prompt for appending a note to today's daily log.
    static func appendDailyNote(
        existingContent: String?,
        note: String,
        date: String
    ) -> (system: String, user: String) {
        let system = """
        You are appending to a daily memory log file. \
        If the file already has content, add the new note under the appropriate section. \
        If the file is empty, create a new daily log with a heading and the note. \
        Use the format: `# Daily Log — YYYY-MM-DD` with `## Time` sections.
        """

        let existing = existingContent ?? ""
        let user = """
        File: `memory/\(date).md`

        EXISTING CONTENT:
        \(existing.isEmpty ? "(empty — create new file)" : existing)

        NEW NOTE TO ADD:
        \(note)

        Output the complete updated file.
        """

        return (system: system, user: user)
    }
}

/// Request body for /v1/chat/completions.
struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool

    struct Message: Encodable {
        let role: String
        let content: String
    }

    init(system: String, user: String, model: String = "openclaw", stream: Bool = false) {
        self.model = model
        self.stream = stream
        self.messages = [
            Message(role: "system", content: system),
            Message(role: "user", content: user)
        ]
    }
}

/// Response from /v1/chat/completions (non-streaming).
struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }

    var text: String? {
        choices.first?.message.content
    }
}
