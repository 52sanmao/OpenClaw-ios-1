import Foundation

/// A saved investigation result for a cron job.
struct SavedInvestigation: Codable, Sendable {
    let jobId: String
    let jobName: String
    let errorText: String
    let resultText: String
    let model: String?
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let investigatedAt: Date

    var investigatedAtFormatted: String {
        Formatters.relativeString(for: investigatedAt)
    }

    var investigatedAtAbsolute: String {
        Formatters.absoluteString(for: investigatedAt)
    }
}

/// Protocol for persisting investigation results.
protocol InvestigationStoring: Sendable {
    func save(_ investigation: SavedInvestigation)
    func load(jobId: String) -> SavedInvestigation?
    func remove(jobId: String)
}

/// UserDefaults-backed implementation. Stores latest investigation per job ID.
struct InvestigationStore: InvestigationStoring {
    private static let keyPrefix = "investigation_"

    func save(_ investigation: SavedInvestigation) {
        guard let data = try? JSONEncoder().encode(investigation) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(investigation.jobId))
    }

    func load(jobId: String) -> SavedInvestigation? {
        guard let data = UserDefaults.standard.data(forKey: Self.key(jobId)) else { return nil }
        return try? JSONDecoder().decode(SavedInvestigation.self, from: data)
    }

    func remove(jobId: String) {
        UserDefaults.standard.removeObject(forKey: Self.key(jobId))
    }

    private static func key(_ jobId: String) -> String {
        "\(keyPrefix)\(jobId)"
    }
}
