import Foundation

struct MemoryGetToolRequest: Encodable, Sendable {
    let tool = "memory_get"
    let sessionKey: String
    let args: Args

    struct Args: Encodable, Sendable {
        let path: String
    }

    init(path: String, sessionKey: String = "agent:orchestrator:main") {
        self.sessionKey = sessionKey
        self.args = Args(path: path)
    }
}

struct MemorySearchToolRequest: Encodable, Sendable {
    let tool = "memory_search"
    let sessionKey: String
    let args: Args

    struct Args: Encodable, Sendable {
        let query: String
    }

    init(query: String, sessionKey: String = "agent:orchestrator:main") {
        self.sessionKey = sessionKey
        self.args = Args(query: query)
    }
}
