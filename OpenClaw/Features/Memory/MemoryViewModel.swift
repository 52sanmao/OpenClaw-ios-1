import Foundation
import Observation

@Observable
@MainActor
final class MemoryViewModel {
    var files: [MemoryFile] = []
    var isLoadingFiles = false
    var fileError: Error?

    var fileContent: MemoryFileContent?
    var isLoadingContent = false
    var contentError: Error?

    var searchResults: [MemorySearchResultDTO.Result] = []
    var isSearching = false
    var searchQuery = ""

    var comments: [MemoryComment] = []

    var isSubmitting = false
    var submitResult: String?
    var submitError: Error?

    private let repository: MemoryRepository
    private let client: GatewayClientProtocol

    init(repository: MemoryRepository, client: GatewayClientProtocol) {
        self.repository = repository
        self.client = client
    }

    // MARK: - File List

    func loadFiles() async {
        isLoadingFiles = true
        do {
            files = try await repository.listFiles()
            fileError = nil
        } catch {
            fileError = error
        }
        isLoadingFiles = false
    }

    // MARK: - File Content

    func loadFile(_ file: MemoryFile) async {
        fileContent = nil
        isLoadingContent = true
        contentError = nil
        comments = []
        submitResult = nil
        submitError = nil
        do {
            let content = try await repository.readFile(path: file.path)
            if content.isEmpty {
                contentError = MemoryError.fileNotFound(file.path)
            } else {
                fileContent = content
            }
        } catch {
            contentError = error
        }
        isLoadingContent = false
    }

    // MARK: - Search

    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        do {
            searchResults = try await repository.search(query: query)
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    // MARK: - Comments

    func addComment(paragraphId: String, lineStart: Int, lineEnd: Int, text: String, preview: String) {
        comments.append(MemoryComment(
            id: UUID(),
            paragraphId: paragraphId,
            lineStart: lineStart,
            lineEnd: lineEnd,
            text: text,
            paragraphPreview: String(preview.prefix(80))
        ))
        Haptics.shared.success()
    }

    func removeComment(_ id: UUID) {
        comments.removeAll { $0.id == id }
    }

    func commentsForParagraph(_ id: String) -> [MemoryComment] {
        comments.filter { $0.paragraphId == id }
    }

    func clearComments() {
        comments.removeAll()
        submitResult = nil
        submitError = nil
    }

    // MARK: - Submit Edits

    func submitEdits(for file: MemoryFile) async {
        guard let content = fileContent else { return }
        isSubmitting = true
        submitError = nil

        let prompt = PromptTemplates.editMemoryFile(
            path: file.path,
            content: content.text,
            comments: comments
        )

        let request = ChatCompletionRequest(system: prompt.system, user: prompt.user)

        do {
            let response: ChatCompletionResponse = try await client.statsPost(
                "v1/chat/completions",
                body: request
            )
            submitResult = response.text ?? "Agent returned no content."
            Haptics.shared.success()
        } catch {
            submitError = error
            Haptics.shared.error()
        }
        isSubmitting = false
    }
}

enum MemoryError: LocalizedError {
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): "File not found: \(path)"
        }
    }
}
