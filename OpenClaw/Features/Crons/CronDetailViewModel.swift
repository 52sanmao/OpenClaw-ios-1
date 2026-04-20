import Foundation
import Observation

@Observable
@MainActor
final class CronDetailViewModel {
    var runs: [CronRun] = []
    var detail: RoutineDetailDTO?
    var isLoading = false
    var isLoadingMore = false
    var error: Error?
    var isTriggering = false
    var isTogglingEnabled = false
    var isDeleting = false
    var hasMore = true

    var totalRuns: Int?

    var isInvestigating = false
    var investigateResult: ChatCompletionResponse?
    var investigationError: Error?
    var previousInvestigation: SavedInvestigation?

    // MARK: - Run Stats (computed from loaded runs)

    var stats: RunStats? {
        guard !runs.isEmpty else { return nil }
        return RunStats(runs: runs)
    }

    struct RunStats {
        let avgDuration: TimeInterval
        let avgTokens: Int
        let totalTokens: Int
        let successRate: Double
        let primaryModel: String?
        let runCount: Int

        init(runs: [CronRun]) {
            runCount = runs.count
            avgDuration = runs.map(\.duration).reduce(0, +) / Double(runCount)
            totalTokens = runs.map(\.totalTokens).reduce(0, +)
            avgTokens = totalTokens / runCount
            let succeeded = runs.filter { $0.status == .succeeded }.count
            successRate = Double(succeeded) / Double(runCount)

            // Most frequent model
            var modelCounts: [String: Int] = [:]
            for run in runs {
                if let m = run.model { modelCounts[m, default: 0] += 1 }
            }
            primaryModel = modelCounts.max(by: { $0.value < $1.value })?.key
        }

        var avgDurationFormatted: String {
            let seconds = Int(avgDuration / 1000)
            if seconds < 60 { return "\(seconds)s" }
            return "\(seconds / 60)m \(seconds % 60)s"
        }
    }

    private(set) var job: CronJob
    private let repository: CronDetailRepository
    let client: GatewayClientProtocol
    private let store: InvestigationStoring
    private let onJobUpdated: () async -> Void
    private static let pageSize = 20

    init(
        job: CronJob,
        repository: CronDetailRepository,
        client: GatewayClientProtocol,
        store: InvestigationStoring,
        onJobUpdated: @escaping () async -> Void
    ) {
        self.job = job
        self.repository = repository
        self.client = client
        self.store = store
        self.onJobUpdated = onJobUpdated
        self.previousInvestigation = store.load(jobId: job.id)
    }

    func loadRuns() async {
        isLoading = true
        do {
            async let resultTask = repository.fetchRuns(jobId: job.id, limit: Self.pageSize, offset: 0)
            async let detailTask = client.loadRoutineDetail(jobId: job.id)
            let (result, detail) = try await (resultTask, detailTask)
            runs = result.runs
            hasMore = result.hasMore
            totalRuns = result.total
            self.detail = detail
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
            let result = try await repository.fetchRuns(jobId: job.id, limit: Self.pageSize, offset: runs.count)
            let existingIds = Set(runs.map(\.id))
            let newRuns = result.runs.filter { !existingIds.contains($0.id) }
            runs.append(contentsOf: newRuns)
            hasMore = result.hasMore && !newRuns.isEmpty
        } catch {
            self.error = error
        }
        isLoadingMore = false
    }

    func triggerRun() async {
        isTriggering = true
        do {
            try await repository.triggerRun(jobId: job.id)
            Haptics.shared.success()
            await loadRuns()
            await onJobUpdated()
        } catch {
            self.error = error
            Haptics.shared.error()
        }
        isTriggering = false
    }

    func toggleEnabled() async {
        isTogglingEnabled = true
        let newEnabled = !job.enabled
        do {
            try await repository.setEnabled(jobId: job.id, enabled: newEnabled)
            job.enabled = newEnabled
            Haptics.shared.success()
            await onJobUpdated()
        } catch {
            self.error = error
            Haptics.shared.error()
        }
        isTogglingEnabled = false
    }

    func deleteRoutine() async -> Bool {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await repository.deleteRoutine(jobId: job.id)
            Haptics.shared.success()
            await onJobUpdated()
            return true
        } catch {
            self.error = error
            Haptics.shared.error()
            return false
        }
    }

    func investigateError() async {
        isInvestigating = true
        investigationError = nil
        investigateResult = nil

        let prompt = PromptTemplates.investigateCronError(
            jobName: job.name,
            jobId: job.id,
            lastError: job.lastError,
            consecutiveErrors: job.consecutiveErrors,
            scheduleDescription: job.scheduleDescription,
            lastRunFormatted: job.lastRunFormatted
        )

        let request = ChatCompletionRequest(system: prompt.system, user: prompt.user)

        do {
            let response = try await client.chatCompletion(request)
            investigateResult = response

            // Save to local storage
            let saved = SavedInvestigation(
                jobId: job.id,
                jobName: job.name,
                errorText: job.lastError ?? "",
                resultText: response.text ?? "",
                model: response.model,
                promptTokens: response.usage?.promptTokens,
                completionTokens: response.usage?.completionTokens,
                totalTokens: response.usage?.totalTokens,
                investigatedAt: Date()
            )
            store.save(saved)
            previousInvestigation = saved

            Haptics.shared.success()
        } catch {
            investigationError = error
            Haptics.shared.error()
        }
        isInvestigating = false
    }
}
