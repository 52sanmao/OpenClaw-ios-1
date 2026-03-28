import Foundation

struct StatsExecRequest: Encodable, Sendable {
    let command: String
}

struct StatsExecResponse: Decodable, Sendable {
    let command: String?
    let exitCode: Int?
    let stdout: String?
    let stderr: String?
    let durationMs: Int?
}
