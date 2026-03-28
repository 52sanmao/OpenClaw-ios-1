import Foundation

struct MemoryGetResponseDTO: Decodable, Sendable {
    let text: String
    let path: String
}

struct MemorySearchResultDTO: Decodable, Sendable {
    let results: [Result]

    struct Result: Decodable, Sendable {
        let text: String?
        let path: String?
        let score: Double?
    }
}
