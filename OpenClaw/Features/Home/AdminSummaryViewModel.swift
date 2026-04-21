import Foundation

/// Loads /api/admin/usage/summary for the dashboard admin overview card.
@MainActor
final class AdminSummaryViewModel: LoadableViewModel<AdminUsageSummaryDTO> {
    init(client: GatewayClientProtocol) {
        super.init(loader: { try await client.stats("api/admin/usage/summary") })
    }
}
