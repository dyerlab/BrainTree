import Foundation

struct Thought: Identifiable, Codable, Sendable {
    let id: UUID
    let content: String
    let createdAt: Date
    let metadata: ThoughtMetadata?

    enum CodingKeys: String, CodingKey {
        case id, content, metadata
        case createdAt = "created_at"
    }
}

struct ThoughtMetadata: Codable, Sendable {
    let source: String?
    let title: String?
    let topics: [String]?
    let tags: [String]?
    let type: String?
    let bearId: String?
    let folder: String?

    enum CodingKeys: String, CodingKey {
        case source, title, topics, tags, type, folder
        case bearId = "bear_id"
    }
}

extension Thought {
    var displayTitle: String {
        if let t = metadata?.title, !t.isEmpty { return t }
        return String(content.prefix(80))
    }

    var source: String { metadata?.source ?? "unknown" }

    var dayKey: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: createdAt)
    }

    /// All tags: union of metadata.tags and metadata.topics
    var allTags: [String] {
        let t = metadata?.topics ?? []
        let b = metadata?.tags ?? []
        return Array(Set(t + b)).sorted()
    }

    var deepLink: URL? {
        switch source {
        case "obsidian":
            let file = [metadata?.folder, metadata?.title]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
            guard !file.isEmpty,
                  let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            else { return nil }
            return URL(string: "obsidian://open?vault=BrainTree&file=\(encoded)")
        case "bear":
            guard let id = metadata?.bearId else { return nil }
            return URL(string: "bear://x-callback-url/open-note?id=\(id)")
        default:
            return nil
        }
    }

    var sourceIcon: String { Self.icon(for: source) }

    static func icon(for source: String) -> String {
        switch source {
        case "email":    return "envelope"
        case "slack":    return "bubble.left.and.bubble.right"
        case "obsidian": return "note.text"
        case "bear":     return "pencil.and.outline"
        case "ios":      return "iphone"
        default:         return "circle"
        }
    }
}
