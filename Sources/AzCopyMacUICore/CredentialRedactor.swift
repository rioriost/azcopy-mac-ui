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

    private static let sensitiveFlagNames: Set<String> = [
        "--source-sas",
        "--destination-sas"
    ]

    public static func redact(_ value: String) -> String {
        var redacted = redactQuerySecrets(in: value)
        for key in sensitiveEnvironmentKeys {
            redacted = redactAssignment(named: key, in: redacted)
        }
        for flag in sensitiveFlagNames {
            redacted = redactAssignment(named: flag, in: redacted)
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
        let pattern = #"https?://[^\s"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        var redacted = value
        let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: value) else { continue }
            let urlText = String(value[range])
            guard var components = URLComponents(string: urlText), let items = components.queryItems else {
                continue
            }

            components.queryItems = items.map { item in
                if sensitiveQueryKeys.contains(item.name.lowercased()) {
                    return URLQueryItem(name: item.name, value: "<redacted>")
                }
                return item
            }

            guard let redactedURLText = components.string,
                  let replacementRange = Range(match.range, in: redacted) else {
                continue
            }
            redacted.replaceSubrange(replacementRange, with: redactedURLText)
        }
        return redacted
    }

    private static func redactAssignment(named key: String, in value: String) -> String {
        value.replacingOccurrences(
            of: "\(key)=([^\\s]+)",
            with: "\(key)=<redacted>",
            options: .regularExpression
        )
    }
}
