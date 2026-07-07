import Foundation

public enum CredentialRedactor {
    private static let sensitiveQueryKeys: Set<String> = [
        "sig", "signature", "sk", "skey", "token", "access_token", "refresh_token"
    ]

    private static let sensitiveEnvironmentKeys: Set<String> = [
        "AZCOPY_SPA_CLIENT_SECRET",
        "AZCOPY_SPA_CERT_PASSWORD",
        "AZCOPY_ACCOUNT_KEY"
    ]

    public static func redact(_ value: String) -> String {
        var redacted = redactQuerySecrets(in: value)
        for key in sensitiveEnvironmentKeys {
            redacted = redactAssignment(named: key, in: redacted)
        }
        return redacted
    }

    public static func redact(environment: [String: String]) -> [String: String] {
        environment.mapValues { _ in "<redacted>" }.merging(
            environment.filter { !sensitiveEnvironmentKeys.contains($0.key) }
        ) { redacted, original in
            original.isEmpty ? redacted : original
        }
    }

    public static func redactForLog(command: [String], environment: [String: String]) -> String {
        let redactedEnvironment = environment
            .sorted { $0.key < $1.key }
            .map { key, value in
                sensitiveEnvironmentKeys.contains(key) ? "\(key)=<redacted>" : "\(key)=\(redact(value))"
            }
            .joined(separator: " ")

        let redactedCommand = command.map(redact).joined(separator: " ")
        return [redactedEnvironment, redactedCommand].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func redactQuerySecrets(in value: String) -> String {
        guard var components = URLComponents(string: value), let items = components.queryItems else {
            return value
        }
        components.queryItems = items.map { item in
            if sensitiveQueryKeys.contains(item.name.lowercased()) {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }
        return components.string ?? value
    }

    private static func redactAssignment(named key: String, in value: String) -> String {
        value.replacingOccurrences(
            of: "\(key)=([^\\s]+)",
            with: "\(key)=<redacted>",
            options: .regularExpression
        )
    }
}

