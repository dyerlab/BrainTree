import Foundation

enum APIError: Error, LocalizedError {
    case missingCredentials
    case invalidURL
    case serverError(Int, service: String = "Server", body: String = "")
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "API keys not configured — open Settings to add them."
        case .invalidURL:
            return "Invalid URL."
        case .serverError(let code, service: let service, body: let body):
            return body.isEmpty ? "\(service) returned \(code)." : "\(service) returned \(code): \(body)"
        case .decodingFailed:
            return "Could not parse the server response."
        }
    }
}
