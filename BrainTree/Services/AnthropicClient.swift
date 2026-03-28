import Foundation

struct AnthropicClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model    = "claude-haiku-4-5-20251001"

    static func synthesize(query: String, context: String) async throws -> String {
        guard let key = KeychainClient.load(.anthropicKey) else {
            throw APIError.missingCredentials
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(key,              forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01",     forHTTPHeaderField: "anthropic-version")

        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 256,
            "system": "You are summarizing search results from Rodney's personal knowledge base. Given the query and matching notes, write 2-3 sentences synthesizing what his notes say about the topic. Be specific. Plain text, no headers.",
            "messages": [[
                "role": "user",
                "content": "Query: \"\(query)\"\n\nMatching notes:\n\(context)"
            ]]
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode, service: "Anthropic")
        }

        struct Response: Decodable {
            struct Block: Decodable { let text: String }
            let content: [Block]
        }
        guard let parsed = try? JSONDecoder().decode(Response.self, from: data),
              let text = parsed.content.first?.text else {
            throw APIError.decodingFailed
        }
        return text
    }
}
