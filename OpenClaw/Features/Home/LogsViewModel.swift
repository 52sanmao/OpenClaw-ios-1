import Foundation

@Observable
@MainActor
final class LogsViewModel {
    var entries: [LogStreamEntry] = []
    var isStreaming = false
    var isPaused = false
    var levelFilter: LogLevelFilter = .all
    var targetFilter = ""
    var error: Error?

    private let client: GatewayClientProtocol
    private var streamTask: Task<Void, Never>?
    private var buffer: [LogStreamEntry] = []
    private let maxEntries = 2000

    init(client: GatewayClientProtocol) {
        self.client = client
    }

    var filteredEntries: [LogStreamEntry] {
        entries.filter { entry in
            let levelMatch = levelFilter == .all || entry.normalizedLevel == levelFilter.rawValue
            let targetMatch = targetFilter.isEmpty || entry.target.lowercased().contains(targetFilter.lowercased())
            return levelMatch && targetMatch
        }
    }

    var levelCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            counts[entry.normalizedLevel, default: 0] += 1
        }
        return counts
    }

    func start() {
        guard !isStreaming else { return }
        isStreaming = true
        error = nil
        entries = []
        buffer = []

        streamTask = Task { @MainActor in
            for await entry in client.streamLogs() {
                guard !Task.isCancelled else { break }
                if isPaused {
                    buffer.append(entry)
                    if buffer.count > maxEntries {
                        buffer.removeFirst(buffer.count - maxEntries)
                    }
                } else {
                    entries.insert(entry, at: 0)
                    if entries.count > maxEntries {
                        entries.removeLast(entries.count - maxEntries)
                    }
                }
            }
            isStreaming = false
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused {
            entries.insert(contentsOf: buffer.reversed(), at: 0)
            buffer.removeAll()
            if entries.count > maxEntries {
                entries.removeLast(entries.count - maxEntries)
            }
        }
    }

    func clear() {
        entries.removeAll()
        buffer.removeAll()
    }
}

enum LogLevelFilter: String, CaseIterable, Identifiable {
    case all, debug, info, warn, error

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:   return "全部"
        case .debug: return "调试"
        case .info:  return "信息"
        case .warn:  return "警告"
        case .error: return "错误"
        }
    }
}
