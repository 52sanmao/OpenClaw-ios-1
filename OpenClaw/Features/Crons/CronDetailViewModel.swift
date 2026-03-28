import Foundation
import Observation

@Observable
@MainActor
final class CronDetailViewModel {
    var runs: [CronRun] = []
    var isLoading = false
    var isLoadingMore = false
    var error: Error?
    var isTriggering = false
    var isTogglingEnabled = false
    var hasMore = true

    var isInvestigating = false
    var investigateResult: ChatCompletionResponse?
    var investigateError: Error?
    var previousInvestigation: SavedInvestigation?

    let job: CronJob
    private let repository: CronDetailRepository
    private let client: GatewayClientProtocol
    private let store: InvestigationStoring
    private let onJobUpdated: () async -> Void
    private static let pageSize = 20

    init(
        job: CronJob,
        repository: CronDetailRepository,
        client: GatewayClientProtocol,
        store: InvestigationStoring = InvestigationStore(),
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
            let result = try await repository.fetchRuns(jobId: job.id, limit: Self.pageSize, offset: 0)
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
            Haptics.shared.success()
            await onJobUpdated()
        } catch {
            self.error = error
            Haptics.shared.error()
        }
        isTogglingEnabled = false
    }

    func investigateError() async {
        isInvestigating = true
        investigateError = nil
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
            let response = try await client.chatCompletion(request, sessionKey: "agent:orchestrator:main")
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
            investigateError = error
            Haptics.shared.error()
        }
        isInvestigating = false
    }
}
