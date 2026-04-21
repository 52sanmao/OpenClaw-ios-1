import Foundation
import Observation

@Observable
@MainActor
final class MemoryViewModel {
    var files: [MemoryFile] = []
    var isLoadingFiles = false
    var fileError: Error?

    var skills: [SkillFile] = []
    var isLoadingSkills = false
    var skillError: Error?

    var skillFiles: [SkillFileEntry] = []
    var isLoadingSkillFiles = false
    var skillFilesError: Error?

    var fileContent: MemoryFileContent?
    var isLoadingContent = false
    var contentError: Error?

    var comments: [MemoryComment] = []

    var isSubmitting = false
    var submitResult: String?
    var submitError: Error?

    var searchResults: [MemorySearchResultDTO] = []
    var isSearching = false
    var searchError: Error?

    private let repository: MemoryRepository
    private let client: GatewayClientProtocol

    init(repository: MemoryRepository, client: GatewayClientProtocol) {
        self.repository = repository
        self.client = client
    }

    // MARK: - File List

    func loadFiles() async {
        isLoadingFiles = true
        AppLogStore.shared.append("MemoryViewModel: 开始刷新记忆文件列表")
        do {
            files = try await repository.listFiles()
            fileError = nil
            AppLogStore.shared.append("MemoryViewModel: 记忆文件列表刷新完成 count=\(files.count)")
        } catch {
            fileError = error
            if let gatewayError = error as? GatewayError,
               case .httpError(404, _) = gatewayError {
                AppLogStore.shared.append("MemoryViewModel: 记忆文件列表刷新失败 error=当前部署未启用 stats/exec；记忆/技能页不可用，但聊天主链路可能仍正常")
            } else {
                AppLogStore.shared.append("MemoryViewModel: 记忆文件列表刷新失败 error=\(error.localizedDescription)")
            }
        }
        isLoadingFiles = false
    }

    // MARK: - Skills List

    func loadSkills() async {
        isLoadingSkills = true
        AppLogStore.shared.append("MemoryViewModel: 开始刷新技能列表")
        do {
            skills = try await repository.listSkills()
            skillError = nil
            AppLogStore.shared.append("MemoryViewModel: 技能列表刷新完成 count=\(skills.count)")
        } catch {
            skillError = error
            if let gatewayError = error as? GatewayError,
               case .httpError(404, _) = gatewayError {
                AppLogStore.shared.append("MemoryViewModel: 技能列表刷新失败 error=当前部署未启用 stats/exec；记忆/技能页不可用，但聊天主链路可能仍正常")
            } else {
                AppLogStore.shared.append("MemoryViewModel: 技能列表刷新失败 error=\(error.localizedDescription)")
            }
        }
        isLoadingSkills = false
    }

    // MARK: - Skill Files

    func loadSkillFiles(_ skill: SkillFile) async {
        skillFiles = []
        isLoadingSkillFiles = true
        skillFilesError = nil
        AppLogStore.shared.append("MemoryViewModel: 开始刷新技能文件 skill=\(skill.id)")
        do {
            skillFiles = try await repository.listSkillFiles(skillId: skill.id)
            AppLogStore.shared.append("MemoryViewModel: 技能文件刷新完成 skill=\(skill.id) count=\(skillFiles.count)")
        } catch {
            skillFilesError = error
            AppLogStore.shared.append("MemoryViewModel: 技能文件刷新失败 skill=\(skill.id) error=\(error.localizedDescription)")
        }
        isLoadingSkillFiles = false
    }

    // MARK: - Skill File Content (via stats/exec)

    func loadSkillFileContent(_ entry: SkillFileEntry) async {
        fileContent = nil
        isLoadingContent = true
        contentError = nil
        AppLogStore.shared.append("MemoryViewModel: 开始读取技能文件 skill=\(entry.skillId) path=\(entry.id)")
        do {
            let text = try await repository.readSkillFile(skillId: entry.skillId, relativePath: entry.id)
            fileContent = MemoryFileContent(path: entry.absolutePath, text: text)
            AppLogStore.shared.append("MemoryViewModel: 技能文件读取完成 path=\(entry.absolutePath)")
        } catch {
            contentError = error
            AppLogStore.shared.append("MemoryViewModel: 技能文件读取失败 path=\(entry.absolutePath) error=\(error.localizedDescription)")
        }
        isLoadingContent = false
    }

    // MARK: - File Content

    func loadFile(_ file: MemoryFile) async {
        fileContent = nil
        isLoadingContent = true
        contentError = nil
        comments = []
        submitResult = nil
        submitError = nil
        AppLogStore.shared.append("MemoryViewModel: 开始读取记忆文件 path=\(file.path)")
        do {
            let content = try await repository.readFile(path: file.path)
            if content.isEmpty {
                contentError = MemoryError.fileNotFound(file.path)
                AppLogStore.shared.append("MemoryViewModel: 记忆文件为空 path=\(file.path)")
            } else {
                fileContent = content
                AppLogStore.shared.append("MemoryViewModel: 记忆文件读取完成 path=\(content.path)")
            }
        } catch {
            contentError = error
            AppLogStore.shared.append("MemoryViewModel: 记忆文件读取失败 path=\(file.path) error=\(error.localizedDescription)")
        }
        isLoadingContent = false
    }

    // MARK: - Comments

    func addComment(paragraphId: String, lineStart: Int, lineEnd: Int, text: String, preview: String) {
        comments.append(MemoryComment(
            id: UUID(),
            paragraphId: paragraphId,
            lineStart: lineStart,
            lineEnd: lineEnd,
            text: text,
            paragraphPreview: String(preview.prefix(300))
        ))
        Haptics.shared.success()
    }

    func removeComment(_ id: UUID) {
        comments.removeAll { $0.id == id }
    }

    func commentsForParagraph(_ id: String) -> [MemoryComment] {
        comments.filter { $0.paragraphId == id }
    }

    func clearSubmitState() {
        submitResult = nil
        submitError = nil
    }

    func clearComments() {
        comments.removeAll()
        clearSubmitState()
    }

    // MARK: - Page Comment

    var pageCommentResult: String?
    var isSubmittingPageComment = false
    var pageCommentError: Error?

    func submitPageComment(path: String, instruction: String) async {
        let prompt = PromptTemplates.pageComment(path: path, instruction: instruction)
        await submitAgentComment(prompt: prompt)
    }

    func submitSkillComment(skill: SkillFile, files: [String], instruction: String) async {
        let prompt = PromptTemplates.skillComment(
            skillId: skill.id,
            skillName: skill.displayName,
            files: files,
            instruction: instruction
        )
        await submitAgentComment(prompt: prompt)
    }

    private func submitAgentComment(prompt: (system: String, user: String)) async {
        isSubmittingPageComment = true
        pageCommentError = nil
        pageCommentResult = nil

        let request = ChatCompletionRequest(system: prompt.system, user: prompt.user)

        do {
            let response = try await client.chatCompletion(request)
            pageCommentResult = response.text ?? "代理未返回内容。"
            Haptics.shared.success()
        } catch {
            pageCommentError = error
            Haptics.shared.error()
        }
        isSubmittingPageComment = false
    }

    func clearPageComment() {
        pageCommentResult = nil
        pageCommentError = nil
    }

    // MARK: - Maintenance Actions

    var maintenanceResult: String?
    var isRunningMaintenance = false
    var maintenanceError: Error?

    func runMaintenanceAction(prompt: (system: String, user: String)) async {
        isRunningMaintenance = true
        maintenanceError = nil
        maintenanceResult = nil

        let request = ChatCompletionRequest(system: prompt.system, user: prompt.user)

        do {
            let response = try await client.chatCompletion(request)
            maintenanceResult = response.text ?? "代理未返回内容。"
            Haptics.shared.success()
        } catch {
            maintenanceError = error
            Haptics.shared.error()
        }
        isRunningMaintenance = false
    }

    // MARK: - Submit Edits

    func submitDraftEdits(for file: MemoryFile, text: String) async {
        isSubmitting = true
        submitError = nil
        submitResult = nil

        let prompt = PromptTemplates.saveMemoryFile(
            path: file.path,
            updatedText: text
        )

        let request = ChatCompletionRequest(system: prompt.system, user: prompt.user)

        do {
            let response = try await client.chatCompletion(request)
            fileContent = MemoryFileContent(path: file.path, text: text)
            submitResult = response.text ?? "代理未返回内容。"
            Haptics.shared.success()
        } catch {
            submitError = error
            Haptics.shared.error()
        }
        isSubmitting = false
    }

    func submitEdits(for file: MemoryFile) async {
        guard let content = fileContent else { return }
        isSubmitting = true
        submitError = nil
        submitResult = nil

        let prompt = PromptTemplates.editMemoryFile(
            path: file.path,
            fullText: content.text,
            comments: comments
        )

        let request = ChatCompletionRequest(system: prompt.system, user: prompt.user)

        do {
            let response = try await client.chatCompletion(request)
            submitResult = response.text ?? "代理未返回内容。"
            Haptics.shared.success()
        } catch {
            submitError = error
            Haptics.shared.error()
        }
        isSubmitting = false
    }

    // MARK: - Search

    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        searchError = nil
        AppLogStore.shared.append("MemoryViewModel: 开始搜索记忆 query=\(trimmed)")
        do {
            searchResults = try await client.searchMemory(query: trimmed, limit: 20)
            AppLogStore.shared.append("MemoryViewModel: 搜索完成 count=\(searchResults.count)")
        } catch {
            searchError = error
            AppLogStore.shared.append("MemoryViewModel: 搜索失败 error=\(error.localizedDescription)")
        }
        isSearching = false
    }

    func clearSearch() {
        searchResults = []
        searchError = nil
    }

}

enum MemoryError: LocalizedError {
    case fileNotFound(String)
    case commandFailed(command: String, exitCode: Int, stderr: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            "未找到文件：\(path)"
        case .commandFailed(let command, let exitCode, let stderr):
            "命令“\(command)”执行失败（退出码 \(exitCode)）\(stderr.isEmpty ? "" : "：\(stderr)")"
        }
    }
}
