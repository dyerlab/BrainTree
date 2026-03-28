import Foundation

struct MCPClient {

    // MARK: - Capture

    static func captureThought(_ content: String) async throws {
        let (url, supabaseKey, mcpKey) = try credentials()
        var req = request(url: url, supabaseKey: supabaseKey, mcpKey: mcpKey)
        req.httpBody = try body("capture_thought", args: [
            "content": content,
            "metadata": ["source": "ios", "capture_method": "voice"]
        ])

        let (_, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode, service: "MCP (capture)")
        }
    }

    // MARK: - Search (semantic vector search → Claude synthesis)

    static func searchThoughts(_ query: String, limit: Int = 5) async throws -> (context: String, results: [SearchResult]) {
        let (url, supabaseKey, mcpKey) = try credentials()
        var req = request(url: url, supabaseKey: supabaseKey, mcpKey: mcpKey)
        req.httpBody = try body("search_thoughts", args: [
            "query": query, "limit": limit, "threshold": 0.5
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.serverError(http.statusCode, service: "MCP (search)", body: body)
        }

        let text = extractText(from: data)
        print("[MCPClient] searchThoughts raw HTTP (\(data.count) bytes): \(String(data: data, encoding: .utf8)?.prefix(300) ?? "n/a")")
        print("[MCPClient] extractedText prefix: \(text.prefix(200))")
        let results = SearchResult.decode(from: text)
        return (context: text, results: results)
    }

    // MARK: - List (tag / type filter)

    static func listThoughts(tag: String? = nil, type: String? = nil) async throws -> [SearchResult] {
        let (url, supabaseKey, mcpKey) = try credentials()
        var req = request(url: url, supabaseKey: supabaseKey, mcpKey: mcpKey)

        var args: [String: Any] = [:]
        if let tag  { args["tag"]  = tag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }
        if let type { args["type"] = type.trimmingCharacters(in: .whitespaces) }
        req.httpBody = try body("list_thoughts", args: args)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.serverError(http.statusCode, service: "MCP (list)", body: body)
        }

        let text = extractText(from: data)
        return SearchResult.decode(from: text)
    }

    // MARK: - Stats (discover available sources)

    static func thoughtStats() async throws -> [String] {
        let (url, supabaseKey, mcpKey) = try credentials()
        var req = request(url: url, supabaseKey: supabaseKey, mcpKey: mcpKey)
        req.httpBody = try body("thought_stats", args: [:])

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode, service: "MCP (stats)")
        }

        return parseSources(from: extractText(from: data))
    }

    // MARK: - Helpers

    private static func credentials() throws -> (URL, String, String) {
        guard let base        = KeychainClient.load(.supabaseURL),
              let supabaseKey = KeychainClient.load(.supabaseKey),
              let mcpKey      = KeychainClient.load(.mcpAccessKey) else {
            throw APIError.missingCredentials
        }
        guard let url = URL(string: "\(base)/functions/v1/open-brain-mcp") else {
            throw APIError.invalidURL
        }
        return (url, supabaseKey, mcpKey)
    }

    private static func request(url: URL, supabaseKey: String, mcpKey: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(supabaseKey,        forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        req.setValue(mcpKey,             forHTTPHeaderField: "x-brain-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private static func body(_ tool: String, args: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": tool, "arguments": args]
        ])
    }

    private static func extractText(from data: Data) -> String {
        struct Item: Decodable { let type: String; let text: String }
        struct Inner: Decodable { let content: [Item] }
        struct Outer: Decodable { let result: Inner?; let content: [Item]? }

        func decodeOuter(_ jsonData: Data) -> String? {
            guard let env = try? JSONDecoder().decode(Outer.self, from: jsonData) else { return nil }
            if let item = env.result?.content.first(where: { $0.type == "text" }) { return item.text }
            if let item = env.content?.first(where: { $0.type == "text" }) { return item.text }
            return nil
        }

        // Try direct JSON first
        if let text = decodeOuter(data) { return text }

        // Handle SSE format: one or more "data: <json>" lines
        let raw = String(data: data, encoding: .utf8) ?? ""
        for line in raw.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            guard stripped.hasPrefix("data:") else { continue }
            let jsonStr = String(stripped.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let jsonData = jsonStr.data(using: .utf8),
                  let text = decodeOuter(jsonData) else { continue }
            return text
        }

        return raw
    }

    /// Parse source names out of whatever thought_stats returns.
    /// Handles: {"sources":{"email":5,...}}, {"sources":["email",...]}, or a flat dict.
    private static func parseSources(from text: String) -> [String] {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        // {"sources": {"email": 5, "slack": 3, ...}}
        if let sources = json["sources"] as? [String: Any] {
            return sources.keys.sorted()
        }
        // {"sources": ["email", "slack", ...]}
        if let sources = json["sources"] as? [String] {
            return sources.sorted()
        }
        // flat {"email": 5, "slack": 3} — treat all string keys as sources
        return json.keys.sorted()
    }
}
