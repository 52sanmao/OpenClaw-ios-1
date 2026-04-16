import Foundation

protocol CronRepository: Sendable {
    func fetchJobs() async throws -> [CronJob]
}

final class RemoteCronRepository: CronRepository {
    private let client: GatewayClientProtocol
    private let cache = MemoryCache<[CronJob]>(ttl: 30)

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    func fetchJobs() async throws -> [CronJob] {
        if let cached = await cache.get() { return cached }
        let routines = try await client.listRoutines()
        let jobs = routines.map(CronJob.init)
        await cache.set(jobs)
        return jobs
    }
}
