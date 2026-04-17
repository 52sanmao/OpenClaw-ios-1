import Foundation

struct MemoryGetResponseDTO: Decodable, Sendable {
    let text: String
    let path: String
}

struct MemoryHTTPListResponseDTO: Decodable, Sendable {
    let entries: [MemoryHTTPEntryDTO]
}

struct MemoryHTTPEntryDTO: Decodable, Sendable {
    let path: String
    let name: String?
    let isDir: Bool?
    let updatedAt: String?
}

struct MemoryHTTPReadResponseDTO: Decodable, Sendable {
    let content: String
    let path: String
    let updatedAt: String?
}
