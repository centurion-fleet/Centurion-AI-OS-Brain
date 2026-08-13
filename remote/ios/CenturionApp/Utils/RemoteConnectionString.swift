import Foundation
import Security

/// Parses and formats remote pairing connection strings:
/// `token:<secret>@<host>:<port>`
enum RemoteConnectionString {
    struct Components: Equatable {
        let token: String
        let host: String
        let port: Int
    }

    static func parse(_ input: String) -> Components? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("token:") else { return nil }
        let rest = String(trimmed.dropFirst("token:".count))
        guard let at = rest.firstIndex(of: "@") else { return nil }
        let token = String(rest[..<at])
        let hostPort = String(rest[rest.index(after: at)...])
        guard !token.isEmpty, !hostPort.isEmpty else { return nil }

        if let colon = hostPort.lastIndex(of: ":") {
            let host = String(hostPort[..<colon])
            let portString = String(hostPort[hostPort.index(after: colon)...])
            if !host.isEmpty, let port = Int(portString), port > 0, port <= 65535 {
                return Components(token: token, host: host, port: port)
            }
        }
        return Components(token: token, host: hostPort, port: 9119)
    }

    static func format(token: String, host: String, port: Int = 9119) -> String {
        "token:\(token)@\(host):\(port)"
    }
}

/// Keychain storage for the remote pairing secret (never UserDefaults).
enum RemotePairingTokenStore {
    private static let service = "com.centurion.ios.remote-pairing-token"
    private static let account = "primary"

    static func save(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        insert[kSecValueData as String] = data
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
