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
        var redacted = replace(
            pattern: #"(https?://)[^\s/@]+@"#,
            template: "$1<redacted>@",
            in: redactJSONSecrets(in: value)
        )
        for key in sensitiveEnvironmentKeys {
            redacted = redactAssignment(named: key, allowsSeparateValue: false, in: redacted)
        }
        for flag in sensitiveFlagNames {
            redacted = redactAssignment(named: flag, allowsSeparateValue: true, in: redacted)
        }
        redacted = replace(
            pattern: #"(\bauthorization[ \t]*[:=][ \t]*(?:Bearer|Basic)[ \t]+)[^\s"',;<>]+"#,
            template: "$1<redacted>",
            in: redacted
        )
        return redactQuerySecrets(in: redacted)
    }

    /// Redacts complete argv entries before any display quoting or joining.
    public static func redact(arguments: [String]) -> [String] {
        var expectsSecret = false
        return arguments.map { argument in
            let name = String(argument.prefix { $0 != "=" })
            if sensitiveFlagNames.contains(name.lowercased()) {
                if argument.contains("=") {
                    expectsSecret = false
                    return "\(name)=<redacted>"
                }
                expectsSecret = true
                return argument
            }
            if expectsSecret {
                expectsSecret = false
                return "<redacted>"
            }
            if argument.contains("="), sensitiveEnvironmentKeys.contains(name.uppercased()) {
                return "\(name)=<redacted>"
            }
            return redact(redactURLArgument(argument))
        }
    }

    /// Quotes only for display, retaining argv boundaries without evaluating a shell.
    public static func quoteArgument(_ argument: String) -> String {
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if !argument.isEmpty, argument.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func redact(environment: [String: String]) -> [String: String] {
        environment.reduce(into: [:]) { result, item in
            result[item.key] = sensitiveEnvironmentKeys.contains(item.key.uppercased()) ? "<redacted>" : redact(item.value)
        }
    }

    public static func redactForLog(command: [String], environment: [String: String]) -> String {
        let redactedEnvironment = redact(environment: environment)
            .sorted { $0.key < $1.key }
            .map { quoteArgument("\($0.key)=\($0.value)") }
            .joined(separator: " ")

        let redactedCommand = redact(arguments: command).map(quoteArgument).joined(separator: " ")
        return [redactedEnvironment, redactedCommand].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func redactQuerySecrets(in value: String) -> String {
        // Match query assignments independently of URL parsing, including bare SAS,
        // percent-encoded keys/delimiters and JSON-escaped URL delimiters.
        let keys = sensitiveQueryKeys.sorted().map { key in
            key.unicodeScalars.map { scalar in
                let hex = String(scalar.value, radix: 16)
                return "(?:\(NSRegularExpression.escapedPattern(for: String(scalar)))|%\(hex)|\\\\u00\(hex))"
            }.joined()
        }.joined(separator: "|")
        let boundary = #"(^|[^A-Za-z0-9_]|%3f|%26|\\u003f|\\u0026)"#
        let literalSeparator = #"(?:=|\\u003d)"#
        let literalSecret = #"(?:(?!&|\\u0026|[\s"'<>]).)+"#
        let encodedSecret = #"(?:(?!&|%26|\\u0026|[\s"'<>]).)+"#
        let redacted = replace(
            pattern: "\(boundary)((?:\(keys))\(literalSeparator))\(literalSecret)",
            template: "$1$2<redacted>",
            in: value
        )
        return replace(
            pattern: "\(boundary)((?:\(keys))%3d)\(encodedSecret)",
            template: "$1$2<redacted>",
            in: redacted
        )
    }

    private static func redactURLArgument(_ argument: String) -> String {
        let prefix: String
        let value: String
        if argument.hasPrefix("-"), let separator = argument.firstIndex(of: "=") {
            prefix = String(argument[...separator])
            value = String(argument[argument.index(after: separator)...])
        } else {
            prefix = ""
            value = argument
        }
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return argument
        }
        var changed = false
        if components.user != nil || components.password != nil {
            components.user = "<redacted>"
            components.password = nil
            changed = true
        }
        if let items = components.queryItems,
           items.contains(where: { sensitiveQueryKeys.contains($0.name.lowercased()) }) {
            components.queryItems = items.map { item in
                sensitiveQueryKeys.contains(item.name.lowercased())
                    ? URLQueryItem(name: item.name, value: "<redacted>")
                    : item
            }
            changed = true
        }
        return changed ? prefix + (components.string ?? "<redacted>") : argument
    }

    private static func redactJSONSecrets(in value: String) -> String {
        let names = sensitiveQueryKeys
            .union(sensitiveEnvironmentKeys)
            .union(["client_secret", "clientSecret", "password", "account_key", "accountKey", "authorization", "source-sas", "destination-sas"])
            .sorted()
            .map(NSRegularExpression.escapedPattern)
            .joined(separator: "|")
        let quotedValue = #"(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')"#
        return replace(
            pattern: "([\"'](?:\(names))[\"']\\s*:\\s*)\(quotedValue)",
            template: "$1\"<redacted>\"",
            in: value
        )
    }

    private static func redactAssignment(named key: String, allowsSeparateValue: Bool, in value: String) -> String {
        let name = NSRegularExpression.escapedPattern(for: key)
        let separator = allowsSeparateValue ? #"(?:=|[ \t]+)"# : "="
        let quotedOrBareValue = #"(?:"(?:\\.|[^"\\])*"|'[^']*'|[^\s"'<>]+)"#
        return replace(
            pattern: "(?<![A-Za-z0-9_])(\(name)\(separator))\(quotedOrBareValue)",
            template: "$1<redacted>",
            in: value
        )
    }

    private static func replace(pattern: String, template: String, in value: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return value
        }
        return expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: template
        )
    }
}
