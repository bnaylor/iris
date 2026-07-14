import Foundation
import Security

public final class KeychainManager: @unchecked Sendable {
    public static let shared = KeychainManager()
    
    private let service = "com.iris.secrets"
    private let account = "all-keys"
    
    private init() {}
    
    public func loadSecrets() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            return [:]
        }
        
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            print("Failed to decode keychain secrets: \(error)")
            return [:]
        }
    }
    
    public func saveSecrets(_ secrets: [String: String]) {
        guard let data = try? JSONEncoder().encode(secrets) else {
            print("Failed to encode secrets")
            return
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            SecItemAdd(newQuery as CFDictionary, nil)
        } else if status != errSecSuccess {
            print("Failed to save secrets to keychain: \(status)")
        }
    }
}
