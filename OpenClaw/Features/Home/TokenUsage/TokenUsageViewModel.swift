import Foundation
import Observation

@Observable
@MainActor
final class TokenUsageViewModel {
    var data: TokenUsage?
    var isLoading = false
    var error: Error?
    var selectedPeriod: TokenPeriod = .today

    var isStale: Bool { error != nil && data != nil }

    private let client: GatewayClientProtocol

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    func start() {
        Task { await load() }
    }

    func refresh() async {
        await load()
    }

    private func load() async {
        if data == nil { isLoading = true }
        do {
            let dto: TokenUsageDTO = try await client.stats("stats/tokens?period=\(selectedPeriod.rawValue)")
            data = TokenUsage(dto: dto)
            error = nil
        } catch let gatewayError as GatewayError {
            if case .httpError(404, _) = gatewayError {
                data = nil
                error = nil
            } else {
                error = gatewayError
            }
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
