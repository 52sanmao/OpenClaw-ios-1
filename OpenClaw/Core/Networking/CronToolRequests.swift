import Foundation

struct CronToolRequest: Encodable, Sendable {
    let tool: String
    let args: Input

    struct Input: Encodable, Sendable {
        let action: String
        let includeDisabled: Bool?
    }

    init(args: Input) {
        self.tool = "cron"
        self.args = args
    }
}

struct CronJobToolRequest: Encodable, Sendable {
    let tool = "cron"
    let args: Args

    struct Args: Encodable, Sendable {
        let action: String
        let jobId: String
    }
}

struct CronRunsToolRequest: Encodable, Sendable {
    let tool = "cron"
    let args: Args

    struct Args: Encodable, Sendable {
        let action = "runs"
        let jobId: String
        let limit: Int
        let offset: Int
    }
}

struct CronUpdateToolRequest: Encodable, Sendable {
    let tool = "cron"
    let args: Args

    struct Args: Encodable, Sendable {
        let action = "update"
        let jobId: String
        let patch: Patch
    }

    struct Patch: Encodable, Sendable {
        let enabled: Bool
    }
}

struct SessionHistoryToolRequest: Encodable, Sendable {
    let tool = "sessions_history"
    let args: Args

    struct Args: Encodable, Sendable {
        let sessionKey: String
        let limit: Int
        let includeTools: Bool
    }
}
