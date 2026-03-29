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
        The workspace root is: \(AppConstants.workspaceRoot)

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

    /// Build a prompt for a skill-level instruction.
    /// The agent reads the SKILL.md first to understand the skill before acting.
    static func skillComment(
        skillId: String,
        skillName: String,
        files: [String],
        instruction: String
    ) -> (system: String, user: String) {

        let system = """
        You have a task: apply a user instruction to a skill.
        The workspace root is: \(AppConstants.workspaceRoot)
        The skill folder is: skills/\(skillId)/

        Before doing ANYTHING, follow these steps in order:
        1. Read the `create-skill` skill first — it is the master guide for how skills are structured, best practices, and conventions. You MUST read this first.
        2. Read `skills/\(skillId)/SKILL.md` — understand what THIS specific skill does, its purpose, scripts, and configuration
        3. If the instruction references specific files, read those too
        4. Only THEN apply the user's instruction — with full knowledge of skill best practices AND this skill's design
        5. If you need to create, edit, or delete files — use the write tool
        6. Reply with a 2-3 bullet summary of what you understood and what you changed

        Rules:
        - Always read create-skill FIRST, then the target skill — never act without understanding both
        - Follow the conventions and structure defined in create-skill
        - Maintain the skill's existing structure unless the instruction says otherwise
        - If the instruction is unclear given the skill's purpose, explain what you'd recommend instead of blindly executing
        - You MUST read before writing — do not guess file contents
        """

        let fileList = files.map { "  - \($0)" }.joined(separator: "\n")
        let user = """
        Skill: `\(skillName)` (folder: \(skillId))
        Files in this skill:
        \(fileList)

        Instruction: \(instruction)
        """

        return (system: system, user: user)
    }

    /// Build a prompt for investigating trace step comments.
    static func investigateTrace(
        sessionKey: String,
        sessionTitle: String,
        comments: [TraceComment]
    ) -> (system: String, user: String) {

        let sessionType = Self.describeSessionType(sessionKey)

        let system = """
        You have a task: investigate user comments on your execution trace(s).
        The workspace root is: \(AppConstants.workspaceRoot)
        Context: This is \(sessionType).

        Steps:
        1. Read the session trace: sessions_history tool with sessionKey: "\(sessionKey)"
        2. For each commented step, locate it by timestamp and investigate
        3. Check if the issue is still active or already resolved (timestamps are from the original run)
        4. If active, diagnose and fix if possible. If stale, say so.

        Rules:
        - Check later steps to see if issues self-resolved
        - For cron traces: check recent run history for recurrence
        - For subagent traces: check if the parent handled the failure
        - Be concise — one paragraph per comment
        """

        var commentBlocks: [String] = []
        for (index, comment) in comments.enumerated() {
            let tsLabel = comment.stepTimestamp ?? "unknown time"
            commentBlocks.append("""
            [\(index + 1)] Step: \(comment.stepTitle) (\(tsLabel))
            Preview: \(comment.stepPreview)
            Comment: \(comment.text)
            """)
        }

        let user = """
        Session: `\(sessionTitle)` (\(sessionType))
        Key: \(sessionKey)

        \(commentBlocks.joined(separator: "\n\n"))

        Investigate each comment. Note that timestamps are from the original run — check if issues are still active or already resolved.
        """

        return (system: system, user: user)
    }

    static func describeSessionType(_ key: String) -> String {
        if key == SessionKeys.main { return "the main \(AppConstants.agentId) session (live chat)" }
        if key.hasPrefix(SessionKeys.cronPrefix) && key.contains(":run:") {
            let jobId = String(key.dropFirst(SessionKeys.cronPrefix.count).split(separator: ":").first ?? "")
            return "an isolated cron job run\(jobId.isEmpty ? "" : " (job: \(jobId))")"
        }
        if key.hasPrefix(SessionKeys.cronPrefix) { return "a persistent cron job session" }
        if key.hasPrefix(SessionKeys.subagentPrefix) { return "a subagent session" }
        return "a session"
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
        The workspace root is: \(AppConstants.workspaceRoot)

        Steps:
        1. Check recent run history: cron tool (action: "runs", jobId: "\(jobId)")
        2. Check if the error is stale (recent runs succeeded) or still active
        3. If active: read referenced scripts/configs, diagnose, and FIX immediately
        4. If stale: report it's resolved

        Reply with: **Status** (Resolved/Fixed/Cannot Fix/Stale), **Root Cause**, **Action Taken**, **Impact**
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
        The workspace root is: \(AppConstants.workspaceRoot)

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

    /// Build a prompt for a page-level instruction on a file.
    static func pageComment(
        path: String,
        instruction: String
    ) -> (system: String, user: String) {

        let system = """
        You have a task: apply a user instruction to an entire file.
        The workspace root is: \(AppConstants.workspaceRoot)

        Steps:
        1. Read the file at the given path using the read tool
        2. Apply the user's instruction to the file as a whole
        3. Save the result using the write tool to the same path
        4. Reply with a 2-3 bullet summary of what you changed

        Rules:
        - Follow the instruction faithfully — it applies to the whole file
        - Maintain existing formatting and structure where the instruction doesn't say otherwise
        - You MUST read then write the file — do not just output content
        """

        let user = """
        File: `\(path)`

        Instruction: \(instruction)
        """

        return (system: system, user: user)
    }

    /// Build a prompt for appending a note to today's daily log.
    static func appendDailyNote(date: String, note: String) -> (system: String, user: String) {
        let system = """
        Append a note to the daily memory log at `memory/\(date).md`.
        If the file doesn't exist, create it with heading `# Daily Log — \(date)`.
        Add the note under an appropriate time section. Save with the write tool.
        """
        return (system: system, user: "Add this note:\n\(note)")
    }
}
