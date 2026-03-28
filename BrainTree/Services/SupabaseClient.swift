import Foundation

struct SupabaseClient {
    static func fetchRecentThoughts(limit: Int = 100) async throws -> [Thought] {
        guard let baseURL = KeychainClient.load(.supabaseURL),
              let key    = KeychainClient.load(.supabaseKey) else {
            throw APIError.missingCredentials
        }

        let urlStr = "\(baseURL)/rest/v1/thoughts"
            + "?select=id,content,metadata,created_at"
            + "&order=created_at.desc"
            + "&limit=\(limit)"

        guard let url = URL(string: urlStr) else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.setValue(key,              forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)",  forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode, service: "Supabase")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let str = try decoder.singleValueContainer().decode(String.self)
            // Supabase returns ISO8601 with fractional seconds
            let formatters: [ISO8601DateFormatter] = [
                { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }(),
                { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }(),
            ]
            for f in formatters {
                if let date = f.date(from: str) { return date }
            }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        return try decoder.decode([Thought].self, from: data)
    }
}
