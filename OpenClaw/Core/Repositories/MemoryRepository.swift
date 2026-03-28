import Foundation

protocol MemoryRepository: Sendable {
    func listFiles() async throws -> [MemoryFile]
    func readFile(path: String) async throws -> MemoryFileContent
    func search(query: String) async throws -> [MemorySearchResultDTO.Result]
}

final class RemoteMemoryRepository: MemoryRepository {
    private let client: GatewayClientProtocol

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    func listFiles() async throws -> [MemoryFile] {
        let body = StatsExecRequest(command: "memory-list")
        let response: StatsExecResponse = try await client.statsPost("stats/exec", body: body)
        return MemoryFile.parse(stdout: response.stdout ?? "")
    }

    func readFile(path: String) async throws -> MemoryFileContent {
        let body = MemoryGetToolRequest(path: path)
        let response: MemoryGetResponseDTO = try await client.invoke(body)
        return MemoryFileContent(path: response.path, text: response.text)
    }

    func search(query: String) async throws -> [MemorySearchResultDTO.Result] {
        let body = MemorySearchToolRequest(query: query)
        let response: MemorySearchResultDTO = try await client.invoke(body)
        return response.results
    }
}
