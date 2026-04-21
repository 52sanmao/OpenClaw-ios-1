import Foundation

// MARK: - List

struct SkillListResponseDTO: Decodable, Sendable {
    let skills: [SkillInfoDTO]
    let count: Int
}

struct SkillInfoDTO: Decodable, Sendable, Identifiable {
    let name: String
    let description: String
    let version: String
    let trust: String
    let source: String
    let keywords: [String]

    var id: String { name }
}

// MARK: - Search

struct SkillSearchRequestDTO: Encodable, Sendable {
    let query: String
}

struct SkillSearchResponseDTO: Decodable, Sendable {
    let catalog: [SkillCatalogEntryDTO]
    let installed: [SkillInfoDTO]
    let registryUrl: String
    let catalogError: String?
}

struct SkillCatalogEntryDTO: Decodable, Sendable, Identifiable {
    let slug: String
    let name: String
    let description: String
    let version: String
    let score: Double?
    let updatedAt: String?
    let stars: Int?
    let downloads: Int?
    let owner: String?
    let installed: Bool

    var id: String { slug }
}

// MARK: - Install / Remove

struct SkillInstallRequestDTO: Encodable, Sendable {
    let name: String
    let slug: String?
    let url: String?
    let content: String?
}

struct ActionResponseDTO: Decodable, Sendable {
    let success: Bool
    let message: String
}
