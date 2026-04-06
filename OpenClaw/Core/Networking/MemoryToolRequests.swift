import Foundation

struct MemoryGetToolRequest: Encodable, Sendable {
    let tool = "memory_get"
    let sessionKey: String
    let args: Args

    struct Args: Encodable, Sendable {
        let path: String
    }

    init(path: String, sessionKey: String) {
        self.sessionKey = sessionKey
        self.args = Args(path: path)
    }
}
