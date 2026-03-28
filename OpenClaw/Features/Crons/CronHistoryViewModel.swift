import Foundation
import Observation

@Observable
@MainActor
final class CronHistoryViewModel {
    var runs: [CronRun] = []
    var isLoading = false
    var isLoadingMore = false
    var error: Error?
    var hasMore = true

    private let repository: CronDetailRepository
    private static let pageSize = 20

    init(repository: CronDetailRepository) {
        self.repository = repository
    }

    func loadRuns() async {
        isLoading = true
        do {
            let result = try await repository.fetchAllRuns(limit: Self.pageSize, offset: 0)
            runs = result.runs
            hasMore = result.hasMore
            error = nil
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let result = try await repository.fetchAllRuns(limit: Self.pageSize, offset: runs.count)
            let existingIds = Set(runs.map(\.id))
            let newRuns = result.runs.filter { !existingIds.contains($0.id) }
            runs.append(contentsOf: newRuns)
            hasMore = result.hasMore && !newRuns.isEmpty
        } catch {
            self.error = error
        }
        isLoadingMore = false
    }
}
