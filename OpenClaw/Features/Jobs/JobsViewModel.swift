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

    func cancelJob(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        try await client.statsPostVoid("api/jobs/\(encoded)/cancel")
    }

    func restartJob(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        try await client.statsPostVoid("api/jobs/\(encoded)/restart")
    }
}
