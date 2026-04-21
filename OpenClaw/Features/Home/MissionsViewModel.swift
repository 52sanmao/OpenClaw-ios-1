import Foundation
import Observation

@Observable
@MainActor
final class MissionsViewModel {
    var missions: [MissionDTO] = []
    var summary: MissionsSummaryDTO?
    var selectedMission: MissionDetailDTO?
    var isLoading = false
    var isLoadingDetail = false
    var isActing = false
    var error: Error?
    var actionError: String?

    private let client: GatewayClientProtocol

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        AppLogStore.shared.append("MissionsViewModel: 加载 missions")

        async let list: MissionsListResponseDTO? = try? client.stats("api/engine/missions")
        async let stat: MissionsSummaryDTO? = try? client.stats("api/engine/missions/summary")
        let (l, s) = await (list, stat)
        missions = l?.missions ?? []
        summary = s
    }

    func loadDetail(id: String) async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            let response: MissionDetailResponseDTO = try await client.stats("api/engine/missions/\(encoded)")
            selectedMission = response.mission
        } catch {
            actionError = error.localizedDescription
        }
    }

    func fireMission(id: String) async {
        isActing = true
        defer { isActing = false }
        do {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            let response: MissionFireResponseDTO = try await client.statsPost("api/engine/missions/\(encoded)/fire", body: EmptyBody())
            if response.fired == true || response.threadId != nil {
                Haptics.shared.success()
            }
            await load()
            await loadDetail(id: id)
        } catch {
            actionError = error.localizedDescription
            Haptics.shared.error()
        }
    }

    func pauseMission(id: String) async {
        isActing = true
        defer { isActing = false }
        do {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            try await client.statsPostVoid("api/engine/missions/\(encoded)/pause")
            Haptics.shared.success()
            await load()
            await loadDetail(id: id)
        } catch {
            actionError = error.localizedDescription
            Haptics.shared.error()
        }
    }

    func resumeMission(id: String) async {
        isActing = true
        defer { isActing = false }
        do {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            try await client.statsPostVoid("api/engine/missions/\(encoded)/resume")
            Haptics.shared.success()
            await load()
            await loadDetail(id: id)
        } catch {
            actionError = error.localizedDescription
            Haptics.shared.error()
        }
    }
}

private struct EmptyBody: Encodable {}
