import Foundation

/// System health VM with auto-polling every 15 seconds.
/// Polling starts when the view appears and stops when it disappears.
@MainActor
final class SystemHealthViewModel: LoadableViewModel<SystemStats> {
    private static let pollInterval: TimeInterval = 15

    init(repository: SystemHealthRepository) {
        super.init(loader: { try await repository.fetch() })
    }

    func startPolling() {
        startPolling(interval: Self.pollInterval)
    }
}
