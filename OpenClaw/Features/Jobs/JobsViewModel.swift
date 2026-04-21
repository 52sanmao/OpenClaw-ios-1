import Foundation
import Observation

@Observable
@MainActor
final class JobsViewModel {
    var jobs: [JobDTO] = []
    var summary: JobsSummaryDTO?
    var isLoading = false
    var error: Error?

    private let client: GatewayClientProtocol

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        AppLogStore.shared.append("JobsViewModel: 加载 /api/jobs 与 /api/jobs/summary")

        async let list: JobsResponseDTO? = try? client.stats("api/jobs")
        async let stat: JobsSummaryDTO? = try? client.stats("api/jobs/summary")
        let (l, s) = await (list, stat)
        jobs = l?.jobs ?? []
        summary = s
    }

    func jobDetail(id: String) async throws -> JobDetailDTO {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await client.stats("api/jobs/\(encoded)")
    }

    func jobEvents(id: String) async throws -> [JobEventDTO] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: JobEventsResponseDTO = try await client.stats("api/jobs/\(encoded)/events")
        return response.events
    }

    func jobFiles(id: String, path: String = "") async throws -> [JobFileEntryDTO] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let escapedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let response: JobFilesListResponseDTO = try await client.stats("api/jobs/\(encoded)/files/list?path=\(escapedPath)")
        return response.entries
    }

    func readJobFile(id: String, path: String) async throws -> JobFileReadResponseDTO {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let escapedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        return try await client.stats("api/jobs/\(encoded)/files/read?path=\(escapedPath)")
    }

    func sendPrompt(id: String, content: String, done: Bool) async throws -> JobPromptResponseDTO {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await client.statsPost("api/jobs/\(encoded)/prompt", body: JobPromptRequestDTO(content: content, done: done))
    }

    func cancelJob(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        try await client.statsPostVoid("api/jobs/\(encoded)/cancel")
    }

    func restartJob(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        try await client.statsPostVoid("api/jobs/\(encoded)/restart")
    }
}
