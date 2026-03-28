import Foundation
import Observation

@Observable
@MainActor
final class CronHistoryViewModel {
    var runs: [CronRun] = []
    var isLoading = false
    var error: Error?

    private let repository: CronDetailRepository
    private let jobsProvider: () -> [CronJob]
    private static let perJobLimit = 10

    init(repository: CronDetailRepository, jobsProvider: @escaping () -> [CronJob]) {
        self.repository = repository
        self.jobsProvider = jobsProvider
    }

    func loadRuns() async {
        let jobs = jobsProvider()
        guard !jobs.isEmpty else { return }

        isLoading = true
        error = nil

        do {
            let allRuns = try await withThrowingTaskGroup(of: [CronRun].self) { group in
                for job in jobs {
                    group.addTask {
                        let page = try await self.repository.fetchRuns(
                            jobId: job.id,
                            limit: Self.perJobLimit,
                            offset: 0
                        )
                        return page.runs
                    }
                }

                var collected: [CronRun] = []
                for try await batch in group {
                    collected.append(contentsOf: batch)
                }
                return collected
            }

            runs = allRuns.sorted { $0.runAt > $1.runAt }
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
