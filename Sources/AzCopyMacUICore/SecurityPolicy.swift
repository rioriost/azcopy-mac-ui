import Foundation

public struct SecurityPolicy: Sendable {
    public enum Violation: Error, Equatable, LocalizedError {
        case missingExecutable
        case executableIsNotAbsolute
        case shellExecutableDisallowed
        case insecureAzureURL(String)
        case accountKeyDirectAuthUnsupported

        public var errorDescription: String? {
            switch self {
            case .missingExecutable:
                "The AzCopy executable path is missing."
            case .executableIsNotAbsolute:
                "The AzCopy executable must be referenced by an absolute path."
            case .shellExecutableDisallowed:
                "Shell execution is not allowed."
            case .insecureAzureURL(let value):
                "Remote storage URLs must use HTTPS: \(CredentialRedactor.redact(arguments: [value]).joined())"
            case .accountKeyDirectAuthUnsupported:
                "Direct account-key authentication is not supported by AzCopy v10."
            }
        }
    }

    public var allowInsecureLocalhost: Bool

    public init(allowInsecureLocalhost: Bool = false) {
        self.allowInsecureLocalhost = allowInsecureLocalhost
    }

    public func validate(invocation: AzCopyInvocation) throws {
        let executablePath = invocation.executableURL.path
        guard !executablePath.isEmpty else { throw Violation.missingExecutable }
        guard executablePath.hasPrefix("/") else { throw Violation.executableIsNotAbsolute }

        let executableName = invocation.executableURL.lastPathComponent
        if ["sh", "bash", "zsh", "fish", "env"].contains(executableName) {
            throw Violation.shellExecutableDisallowed
        }

        for argument in invocation.arguments {
            try validateURLString(argument)
        }

        if invocation.environment.keys.contains("AZCOPY_ACCOUNT_KEY") {
            throw Violation.accountKeyDirectAuthUnsupported
        }
    }

    private func validateURLString(_ value: String) throws {
        let candidate: String
        if value.hasPrefix("-"), let separator = value.firstIndex(of: "=") {
            candidate = String(value[value.index(after: separator)...])
        } else {
            candidate = value
        }
        guard let url = URLComponents(string: candidate.trimmingCharacters(in: .whitespacesAndNewlines)),
              let rawHost = url.host,
              let scheme = url.scheme?.lowercased() else {
            return
        }
        var host = rawHost.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        if host.hasSuffix(".") { host.removeLast() }

        if scheme == "https" {
            return
        }

        let isAzureStorage = [".blob.core.", ".file.core.", ".dfs.core."].contains { host.contains($0) }
        guard scheme == "http" || isAzureStorage else { return }

        if scheme == "http", allowInsecureLocalhost, ["localhost", "127.0.0.1", "::1"].contains(host) {
            return
        }

        throw Violation.insecureAzureURL(CredentialRedactor.redact(arguments: [candidate]).joined())
    }
}
