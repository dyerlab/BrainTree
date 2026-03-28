import Foundation
import Security

enum SecretsKey: String, CaseIterable {
    case supabaseURL    = "supabaseURL"
    case supabaseKey    = "supabaseKey"
    case mcpAccessKey   = "mcpAccessKey"
    case anthropicKey   = "anthropicKey"

    var displayName: String {
        switch self {
        case .supabaseURL:  return "Supabase URL"
        case .supabaseKey:  return "Supabase Key (service_role)"
        case .mcpAccessKey: return "MCP Access Key"
        case .anthropicKey: return "Anthropic API Key"
        }
    }

    var isSecret: Bool { self != .supabaseURL }
}

struct KeychainClient {
    // Shared access group — readable by both main app and widget extension.
    // Format: <TeamID>.<BundleID>  (matches the entitlement $(AppIdentifierPrefix)com.dyerlab.BrainTree)
    static let accessGroup = "3L9D67FVN7.com.dyerlab.BrainTree"
    private static let service = "com.dyerlab.openbrain"

    @discardableResult
    static func save(_ value: String, for key: SecretsKey) -> Bool {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     key.rawValue,
            kSecAttrAccessGroup: accessGroup,
        ]
        let attrs: [CFString: Any] = [
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            attrs.forEach { add[$0] = $1 }
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func load(_ key: SecretsKey) -> String? {
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     key.rawValue,
            kSecAttrAccessGroup: accessGroup,
            kSecReturnData:      true,
            kSecMatchLimit:      kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: SecretsKey) {
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     key.rawValue,
            kSecAttrAccessGroup: accessGroup,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var allPresent: Bool {
        SecretsKey.allCases.allSatisfy { load($0) != nil }
    }
}
