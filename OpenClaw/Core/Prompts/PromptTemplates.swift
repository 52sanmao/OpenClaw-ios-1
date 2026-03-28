import Foundation

/// Centralized prompt templates for agent-mediated actions.
/// Edit this file to tune prompts — all templates in one place.
enum PromptTemplates {

    /// Context lines to include before/after the target section for safety.
    private static let contextPadding = 2

    /// Build a prompt for editing a memory file based on user comments.
    static func editMemoryFile(
        path: String,
        fullText: String,
        comments: [MemoryComment]
    ) -> (system: String, user: String) {

        let system = """
        You have a task: update a workspace markdown file based on user comments.
        The workspace root is: ~/.openclaw/workspace/orchestrator/

        Steps:
        1. Read the file at the given path using the read tool
        2. Apply each comment to the specified line range
        3. Save the result using the write tool to the same path
        4. Reply with a 2-3 bullet summary of changes

        Rules:
        - Only change lines mentioned in comments — preserve everything else
        - Maintain markdown formatting and structure
        - You MUST read then write the file — do not just output content
        """

        let lines = fullText.components(separatedBy: "\n")
        var commentBlocks: [String] = []

        for (index, comment) in comments.enumerated() {
            let safeStart = max(0, comment.lineStart - contextPadding)
            let safeEnd = min(lines.count - 1, comment.lineEnd + contextPadding)
            let contextLines = lines[safeStart...safeEnd].joined(separator: "\n")

            let lineLabel = comment.lineStart == comment.lineEnd
                ? "line \(comment.lineStart + 1)"
                : "lines \(comment.lineStart + 1)-\(comment.lineEnd + 1)"

            commentBlocks.append("""
            [\(index + 1)] \(lineLabel):
            ```
            \(contextLines)
            ```
            Change: \(comment.text)
            """)
        }

        let user = """
        File: `\(path)`
        Total lines: \(lines.count)

        \(commentBlocks.joined(separator: "\n\n"))
        """

        return (system: system, user: user)
    }

    /// Build a prompt for investigating a cron job error.
    static func investigateCronError(
        jobName: String,
        jobId: String,
        lastError: String?,
        consecutiveErrors: Int,
        scheduleDescription: String,
        lastRunFormatted: String
    ) -> (system: String, user: String) {

        let system = """
        You have a task: investigate and FIX a cron job error. Do not just report — take action.
        The workspace root is: ~/.openclaw/workspace/orchestrator/

        Investigation steps:
        1. Check recent run history: cron tool (action: "runs", jobId: "\(jobId)")
        2. Look at the latest run's session log if available
        3. Check if the error is stale (already fixed by a recent successful run) or still active
        4. If the error references a script, config, or file — read it and check for issues

        Decision:
        - If the error is STALE (recent runs succeeded): report it's resolved, no action needed
        - If the error is ACTIVE: diagnose the root cause, then FIX it immediately
          - Fix scripts, configs, permissions, or whatever is broken
          - If the fix requires editing a file, use the write tool
          - If the fix requires running a command, use the exec tool
          - If you cannot fix it (e.g. external service down), explain why clearly

        After investigating (and fixing if needed), reply with this format:

        **Status**: Resolved / Fixed / Cannot Fix / Stale
        **Root Cause**: One-line explanation
        **Action Taken**: What you did (or "None — error was stale")
        **Impact**: What was affected and current state
        """

        let errorText = lastError ?? "No error message available"
        let user = """
        Job: `\(jobName)` (id: \(jobId))
        Schedule: \(scheduleDescription)
        Last run: \(lastRunFormatted)
        Consecutive errors: \(consecutiveErrors)

        Error:
        ```
        \(errorText)
        ```

        Investigate this error and report your findings.
        """

        return (system: system, user: user)
    }

    /// Build a prompt for investigating a command result with AI.
    static func investigateCommandResult(
        commandName: String,
        output: String,
        isSuccess: Bool
    ) -> (system: String, user: String) {

        let system = """
        You have a task: investigate the output of a server command and take action if needed.
        The workspace root is: ~/.openclaw/workspace/orchestrator/

        The user ran a command from the OpenClaw iOS app. You are seeing the full output.

        Steps:
        1. Analyse the output — look for errors, warnings, issues, or anything unusual
        2. If everything looks healthy, say so briefly
        3. If there are issues you CAN fix (config, scripts, permissions, services):
           - Fix them immediately using your tools (exec, write, read)
           - Report what you fixed
        4. If there are issues you CANNOT fix (hardware, external services, needs human):
           - Explain clearly what's wrong and what the user should do

        Keep it concise. Reply with:
        **Status**: Healthy / Issues Found / Fixed / Needs Attention
        **Summary**: 2-3 bullet points of what you found
        **Action Taken**: What you fixed (or "None needed")
        """

        let statusLabel = isSuccess ? "completed successfully" : "failed"
        let user = """
        Command: `\(commandName)` (\(statusLabel))

        Output:
        ```
        \(output)
        ```

        Analyse this output. Fix any issues you can, report what you find.
        """

        return (system: system, user: user)
    }

    /// Build a prompt for appending a note to today's daily log.
    static func appendDailyNote(
        date: String,
        note: String
    ) -> (system: String, user: String) {
        let system = """
        You have a task: append a note to today's daily memory log.

        Steps:
        1. Read the file at `memory/\(date).md` (may not exist yet)
        2. If empty/missing, create with heading `# Daily Log — \(date)`
        3. Add the note under an appropriate time section
        4. Save using the write tool
        5. Reply confirming what was added
        """

        let user = "Add this note:\n\(note)"

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
    let usage: Usage?
    let model: String?

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    var text: String? {
        choices.first?.message.content
    }
}
