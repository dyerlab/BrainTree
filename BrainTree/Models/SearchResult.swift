import Foundation

struct SearchResult: Identifiable, Sendable {
    let id: UUID
    let content: String
    let title: String?
    let source: String?
    let similarity: Double?
    let bearId: String?
    let folder: String?

    var displayTitle: String { title ?? String(content.prefix(80)) }

    var similarityLabel: String? {
        guard let s = similarity else { return nil }
        return "\(Int(s * 100))%"
    }

    var deepLink: URL? {
        switch source {
        case "obsidian":
            let file = [folder, title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
            guard !file.isEmpty,
                  let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            else { return nil }
            return URL(string: "obsidian://open?vault=BrainTree&file=\(encoded)")
        case "bear":
            guard let id = bearId else { return nil }
            return URL(string: "bear://x-callback-url/open-note?id=\(id)")
        default:
            return nil
        }
    }

    var sourceIcon: String { Thought.icon(for: source ?? "unknown") }
}

// MARK: - Flexible decoding from MCP response

extension SearchResult {
    static func decode(from mcpText: String) -> [SearchResult] {
        guard let data = mcpText.data(using: .utf8) else { return [] }

        // Try JSON array
        if let results = try? JSONDecoder().decode([RawResult].self, from: data), !results.isEmpty {
            print("[SearchResult] decoded via JSON array: \(results.count) results")
            return results.map(\.asSearchResult)
        }
        // Try {"results":[...]} or {"thoughts":[...]}
        if let wrapped = try? JSONDecoder().decode([String: [RawResult]].self, from: data),
           let results = wrapped["results"] ?? wrapped["thoughts"], !results.isEmpty {
            print("[SearchResult] decoded via wrapped JSON: \(results.count) results")
            return results.map(\.asSearchResult)
        }

        // MCP returns labeled text blocks — parse line by line
        let parsed = parseTextBlocks(mcpText)
        print("[SearchResult] text-block parse: \(parsed.count) results, text prefix: \(mcpText.prefix(120))")
        for (i, r) in parsed.enumerated() {
            print("[SearchResult]   [\(i)] source=\(r.source ?? "nil") bearId=\(r.bearId ?? "nil") title=\(r.title ?? "nil") deepLink=\(r.deepLink?.absoluteString ?? "nil")")
        }
        if !parsed.isEmpty { return parsed }

        // Last resort: whole text as single result for Claude to synthesize from
        print("[SearchResult] fallback to raw-text result")
        return [SearchResult(id: UUID(), content: mcpText, title: nil, source: nil,
                             similarity: nil, bearId: nil, folder: nil)]
    }

    /// Returns the value after a matching prefix (case-insensitive match via lowercased line,
    /// value extracted from original-case line).
    private static func fieldValue(_ lowercasedLine: String, _ originalLine: String, prefixes: [String]) -> String? {
        for prefix in prefixes {
            if lowercasedLine.hasPrefix(prefix) {
                return String(originalLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Parses the actual MCP response format:
    ///   --- Result 1 (61.5% match) ---
    ///   Source: bear
    ///   Title: Ashby & Requisite Variety
    ///   Bear-ID: AF2F38E9-...
    ///   #tag1 #tag2
    ///   ---
    ///   <content body>
    private static func parseTextBlocks(_ text: String) -> [SearchResult] {
        let lines = text.components(separatedBy: .newlines)
        var results: [SearchResult] = []
        var blockLines: [String] = []
        var currentSimilarity: Double? = nil

        func flushBlock() {
            guard !blockLines.isEmpty else { return }
            if let r = parseBlock(blockLines, similarity: currentSimilarity) { results.append(r) }
            blockLines = []
        }

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            // "--- Result N (XX.X% match) ---" starts a new block
            if t.hasPrefix("---") && t.hasSuffix("---") && t.lowercased().contains("result") {
                flushBlock()
                currentSimilarity = extractSimilarity(from: t)
            } else {
                blockLines.append(line)
            }
        }
        flushBlock()
        return results
    }

    private static func extractSimilarity(from header: String) -> Double? {
        guard let r = header.range(of: #"(\d+\.?\d*)%"#, options: .regularExpression) else { return nil }
        let numStr = header[r].replacingOccurrences(of: "%", with: "")
        return Double(numStr).map { $0 / 100.0 }
    }

    private static func parseBlock(_ lines: [String], similarity: Double?) -> SearchResult? {
        var source: String?
        var title: String?
        var bearId: String?
        var folder: String?
        var contentLines: [String] = []
        var inContent = false

        for line in lines {
            let t  = line.trimmingCharacters(in: .whitespaces)
            let tl = t.lowercased()

            if !inContent && t == "---" { inContent = true; continue }

            if inContent {
                contentLines.append(t)
            } else {
                if      let v = fieldValue(tl, t, prefixes: ["source: "])                             { source = v.lowercased() }
                else if let v = fieldValue(tl, t, prefixes: ["title: "])                              { title  = v }
                else if let v = fieldValue(tl, t, prefixes: ["bear-id: ","bear id: ","bear_id: "])    { bearId = v }
                else if let v = fieldValue(tl, t, prefixes: ["folder: "])                             { folder = v }
                // skip: Captured:, Type:, tag lines (#...), empty lines
            }
        }

        let content = contentLines.filter { !$0.isEmpty }.joined(separator: "\n")
        guard !content.isEmpty || source != nil || title != nil else { return nil }

        return SearchResult(id: UUID(), content: content, title: title, source: source,
                            similarity: similarity, bearId: bearId, folder: folder)
    }

    private struct RawResult: Decodable {
        let id: String?
        let content: String?
        let similarity: Double?
        let metadata: RawMeta?
        // Some MCP responses hoist metadata fields to top level
        let title: String?
        let source: String?
        let folder: String?
        let bearId: String?

        enum CodingKeys: String, CodingKey {
            case id, content, similarity, metadata, title, source, folder
            case bearId = "bear_id"
        }

        struct RawMeta: Decodable {
            let title: String?
            let source: String?
            let folder: String?
            let bearId: String?
            enum CodingKeys: String, CodingKey {
                case title, source, folder
                case bearId = "bear_id"
            }
        }

        var asSearchResult: SearchResult {
            SearchResult(
                id: id.flatMap { UUID(uuidString: $0) } ?? UUID(),
                content: content ?? "",
                title: title ?? metadata?.title,
                source: source ?? metadata?.source,
                similarity: similarity,
                bearId: bearId ?? metadata?.bearId,
                folder: folder ?? metadata?.folder
            )
        }
    }
}
