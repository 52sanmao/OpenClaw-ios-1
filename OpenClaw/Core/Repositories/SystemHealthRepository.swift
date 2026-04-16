import Foundation

protocol SystemHealthRepository: Sendable {
    func fetch() async throws -> SystemStats
}

final class RemoteSystemHealthRepository: SystemHealthRepository {
    private let client: GatewayClientProtocol
    private let cache = MemoryCache<SystemStats>(ttl: 10)

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    func fetch() async throws -> SystemStats {
        if let cached = await cache.get() { return cached }

        do {
            let dto: SystemStatsDTO = try await client.stats("stats/system")
            let model = SystemStats(dto: dto)
            await cache.set(model)
            return model
        } catch let error as GatewayError {
            switch error {
            case .httpError(404, _):
                let fallback = try await statusFallback()
                await cache.set(fallback)
                return fallback
            default:
                throw error
            }
        }
    }

    private func statusFallback() async throws -> SystemStats {
        struct GatewayStatusDTO: Decodable {
            let uptimeSecs: Double?
            let totalConnections: Int?
            let sseConnections: Int?
            let wsConnections: Int?
            let actionsThisHour: Int?
        }

        let dto: GatewayStatusDTO = try await client.stats("api/gateway/status")
        let activity = Double((dto.totalConnections ?? 0) + (dto.sseConnections ?? 0) + (dto.wsConnections ?? 0) + (dto.actionsThisHour ?? 0))
        let synthetic = SystemStatsDTO(
            cpuPercent: 0,
            ramUsedMb: 0,
            ramTotalMb: 0,
            ramPercent: 0,
            diskUsedMb: 0,
            diskTotalMb: 0,
            diskPercent: 0,
            loadAvg1M: activity,
            loadAvg5M: activity,
            uptimeSeconds: dto.uptimeSecs ?? 0,
            timestamp: Int(Date().timeIntervalSince1970)
        )
        return SystemStats(dto: synthetic)
    }
}
