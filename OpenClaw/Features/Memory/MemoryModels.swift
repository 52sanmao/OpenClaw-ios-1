import Foundation

/// A workspace file entry from the memory-list command.
struct MemoryFile: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let kind: Kind

    enum Kind: Sendable {
        case bootstrap  // Root files: MEMORY.md, SOUL.md, etc.
        case dailyLog   // memory/YYYY-MM-DD.md
        case reference  // memory/other.md
    }

    var icon: String {
        switch kind {
        case .bootstrap: "doc.text.fill"
        case .dailyLog:  "calendar"
        case .reference: "bookmark.fill"
        }
    }

    /// Parse the memory-list stdout into structured file entries.
    static func parse(stdout: String) -> [MemoryFile] {
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let separator = lines.firstIndex(of: "---") else {
            return lines.filter { !$0.isEmpty }.map { bootstrapFile($0) }
        }

        let bootstrapLines = lines[..<separator].filter { !$0.isEmpty }
        let logLines = lines[(separator + 1)...].filter { !$0.isEmpty }

        var files: [MemoryFile] = bootstrapLines.map { bootstrapFile($0) }

        for fullPath in logLines {
            let name = (fullPath as NSString).lastPathComponent
            let kind: Kind = name.range(of: #"^\d{4}-\d{2}-\d{2}\.md$"#, options: .regularExpression) != nil ? .dailyLog : .reference
            files.append(MemoryFile(id: fullPath, name: name, path: "memory/\(name)", kind: kind))
        }

        return files
    }

    private static func bootstrapFile(_ name: String) -> MemoryFile {
        MemoryFile(id: name, name: name, path: name, kind: .bootstrap)
    }

    init(id: String, name: String, path: String, kind: Kind) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
    }

    init(path: String, name: String) {
        self.id = path
        self.name = name
        self.path = path
        self.kind = .reference
    }
}

/// Result from memory_get tool with pre-computed paragraphs.
struct MemoryFileContent: Sendable {
    let path: String
    let text: String
    let paragraphs: [MemoryParagraph]
    var isEmpty: Bool { text.isEmpty }

    init(path: String, text: String) {
        self.path = path
        self.text = text
        self.paragraphs = Self.splitParagraphs(path: path, text: text)
    }

    private static func splitParagraphs(path: String, text: String) -> [MemoryParagraph] {
        var result: [MemoryParagraph] = []
        var currentLines: [String] = []
        var startLine = 0
        let lines = text.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty && !currentLines.isEmpty {
                result.append(MemoryParagraph(
                    id: "\(path):\(startLine)",
                    lineStart: startLine,
                    lineEnd: index - 1,
                    text: currentLines.joined(separator: "\n")
                ))
                currentLines = []
                startLine = index + 1
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                if currentLines.isEmpty { startLine = index }
                currentLines.append(line)
            }
        }

        if !currentLines.isEmpty {
            result.append(MemoryParagraph(
                id: "\(path):\(startLine)",
                lineStart: startLine,
                lineEnd: lines.count - 1,
                text: currentLines.joined(separator: "\n")
            ))
        }

        return result
    }
}

struct MemoryParagraph: Identifiable, Sendable {
    let id: String
    let lineStart: Int
    let lineEnd: Int
    let text: String
}

/// A user comment on a specific paragraph.
struct MemoryComment: Identifiable, Sendable {
    let id: UUID
    let paragraphId: String
    let lineStart: Int
    let lineEnd: Int
    let text: String
    let paragraphPreview: String
}
